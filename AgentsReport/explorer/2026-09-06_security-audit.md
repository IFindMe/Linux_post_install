# Security Audit — Command-Execution Surfaces, Chat Authorization, Secret Handling

**Date:** 2026-09-06
**Explorer:** read-only investigation
**Scope:** `bin/`, `lib/`, `scripts/`, `install.sh`, `preinstall.sh`, `postinstall.sh`, `apps/`, `entertainment/`

## TL;DR

- **Telegram listener skips SENDER authorization entirely.** It filters *only on chat id* (`TELEGRAM_CHAT_ID`), and even that filter is weakened by an OR-clause that also accepts `from_id`. No `from.username`/owner-user-id allowlist exists anywhere; there is no config key for one. Anyone who can get a message into the owner chat (shared chat, forwarded/mention, or a group where the bot sees the message with `from_id != chat_id`) can execute arbitrary mapped bash **and** the Gemini AI bridge as your user. This is the single highest-severity finding.
- **Matrix listener DOES implement exactly "sender authorized AND chat authorized"**, but both are *optional-to-configure*: `MATRIX_USER_ID` defaults to a live `/whoami` resolution and `MATRIX_ROOM_ID` to "every room joined". If both are unset at runtime you get "any sender, any room" — remote code execution. Severity depends on which homeserver/rooms the account is in.
- **AI command auto-execution (`pos ai` eval path)** is a real RCE primitive. Trusted aliases pass `--trust` (no confirmation). The listener's `<prefix>` bridge passes *unvalidated chat text* into a shell string that is executed by `bash -c` — a direct RCE.
- **`/dev/tcp` probes interpolate unvalidated host/port into `bash -c` strings** in 4 places. Most reachable inputs are CLI args (interactive/low risk), but `pos-network-download` (`NET_PROBE`, network-derived) and the `share_port_probe` surface deserve review.
- **Backup GPG passphrase** is passed on the gpg **command line** (`--passphrase "$PASS"`) → visible in `ps`/process args, and exported into any `notify`/log context via `set -x` if debugging. No temp files persist the secret; `mktemp` artifacts are cleaned on both success and failure, and the archive is `chmod 600`. The SMB client and Matrix login write credentials to throwaway/templated files correctly (`chmod 600`) and avoid argv exposure, but the SMB persistent credentials dir text is world-readable risk only via file perms (mode 600).

---

## 1. Command-Execution Inventory

All primitives below were located by grep across the specified paths; input provenance chain and classification are traced from source.

### `/dev/tcp` probes — host/port interpolated into `bash -c` string

| ID | file:line | primitive | input source | attacker-controlled? | classification |
|----|-----------|-----------|--------------|----------------------|----------------|
| C01 | `bin/pos-network-checkport:133` | `bash -c "exec 3<>/dev/tcp/$ip/$port"` | `ip` from CLI arg (`$host` from targets, validated no-spaces at :486), `port` validated `[0-9]{1,5}` 1-65535 | port no; host partially (no-space check only, IPv6 brackets stripped) | **REVIEW** — host could contain `;`/`$(...)` if crafted (only `*" "` is rejected; `;`, backticks, `$()` not blocked). Interactive CLI, but the string is unquoted. |
| C02 | `bin/pos-network-checkport:157` | `bash -c "exec 3<>/dev/udp/$ip/$port; printf 'x' >&3"` | same provenance | same | **REVIEW** |
| C03 | `bin/pos-network-checkport:166` | `bash -c ".../dev/tcp/$ip/$port; printf 'HEAD...'"` | same | same | **REVIEW** |
| C04 | `bin/pos-network-checkport:168` | `bash -c ".../dev/tcp/$ip/$port; head -c 200"` | same | same | **REVIEW** |
| C05 | `bin/pos-share-smb-client:92` | `timeout 3 bash -c "exec 3<>/dev/tcp/${host}/${SMB_PORT}"` | `host` from `//server/share` CLI arg; `split_share` extracts `SERVER` with no validation | **partially** — no filtering of `;`/`$()`/backticks in SERVER | **VULNERABLE-INPUT** (low exploitability: requires the operator to type such a host; but a malicious remote `//<payload>/share` string reaches shell). |
| C06 | `lib/share-lib.sh:59` | `timeout 3 bash -c "exec 3<>/dev/tcp/${1}/${2}"` | `$1`=host, `$2`=port from callers (nfs/smb client mounts) | host unvalidated | **VULNERABLE-INPUT** (shared helper; called from CLI-only paths). |
| C07 | `bin/pos-network-download:28,377` | `NET_PROBE=...bash -c '</dev/tcp/8.8.8.8/53>'`; `net_up() { bash -c "$NET_PROBE" }` | **controlled by `NET_PROBE` env var** | **yes** if `NET_PROBE` is attacker-set (e.g. via schedule/daemon env) | **REVIEW** — env-derived command string evaluated; DEFAULT is constant/safe. |

### Listener command execution (chat-driven)

| ID | file:line | primitive | input source | attacker-controlled? | classification |
|----|-----------|-----------|--------------|----------------------|----------------|
| C08 | `bin/pos-communication-telegram-listener:349` | `timeout "$tmo" bash -c "$cmdline"` (in `run_and_reply`) | `$cmdline` = map value (constant, owner-edited) **or** prefix bridge `$cmd $qtext` where `$qtext` = `printf '%q'` of chat text | `$qtext` is the chat text, but `%q`-quoted (safe metachar-wise) | **REVIEW** — map value is constant; prefix path quotes the arg. Map value itself is operator-owned. |
| C09 | `bin/pos-communication-telegram-listener:697` | `run_and_reply "$cmd $qtext" ...` | prefix bridge: `$cmd` = map value (operator), `$qtext` = `%q` quoted chat text | chat text via `%q` (safe) | **REVIEW/SAFE** — quoting present but the whole string is one `bash -c`; the chat text is not the only component. |
| C10 | `bin/pos-communication-matrix-listener:493` | `timeout 60 bash -c "$value"` | `$value` = map value (operator-owned, /cmd) | no (constant operator string) | **SAFE** (constant owner map). |
| C11 | `bin/pos-communication-matrix-listener:214` | `timeout 60 bash -c "$value"` (ui test) | operator input in TUI | no | **SAFE/DESIGNED-INTERACTIVE**. |
| C12 | `bin/pos-communication-telegram-listener:368` | `timeout 60 bash -c "$value"` (ui test) | operator input in TUI | no | **SAFE/DESIGNED-INTERACTIVE**. |

### AI command eval (RCE primitive)

| ID | file:line | primitive | input source | attacker-controlled? | classification |
|----|-----------|-----------|--------------|----------------------|----------------|
| C13 | `bin/pos-ai:388,403` | `run eval "$cmd"` (in `_prompt_run_command`) | `$cmd` = `_extract_commands` of the **AI provider's raw response** (gemini/openrouter/llamacpp output) | **yes — AI-generated** | **VULNERABLE-INPUT** (eval of untrusted model output). Trusted mode (`--trust`, `TRUST_MODE=1`) at :385-388 auto-executes with no prompt; non-trusted prompts on tty. Called from `cmd_ask:535` and `cmd_chat:572`. |
| C14 | `bin/pos-communication-telegram-listener:734` | `timeout 120 pos ai gemini ask ... "$prompt"` | AI bridge: `$prompt` = chat text after `<prefix> ` | chat text — but only as an **argument** to `pos ai gemini ask` (a subprocess arg, quoted via `"$prompt"`); the AI eval inside pos-ai then acts on the model's *reply*. | **REVIEW** — the bridge feeds arbitrary chat text to the model; if the model echoes back a command, C13 fires. Indirect injection. |
| C15 | `bin/pos-communication-matrix-listener:472` | `pos ai gemini ask ... "$prompt"` | same AI bridge (Matrix `ai ` prefix) | same | **REVIEW** (indirect). |

### `sudo` / `systemctl` / docker / ssh / curl|sh

- **`apps/**/*.sh`** — `sudo` used for `apt install`/`systemctl`/`usermod`/`curl | sh` installers. These run **once interactively at install time**; inputs are (mostly) constant URLs. Classified **SAFE/DESIGNED-INTERACTIVE**. Notable pipe-to-shell:
  - `apps/networking/zerotier.sh:9` — `curl -s https://install.zerotier.com | sudo bash` (network→shell, no verification). **Review**.
  - `apps/networking/netbird.sh:9`, `tailscale.sh:9` — `curl -fsSL ... | sh` (official vendor identical). **Review** (no checksum; standard vendor practice).
  - `apps/system/docker.sh:9` — `curl -fsSL https://get.docker.com | sh`. **Review**.
  - `apps/development/opencode.sh:9` — `curl -fsSL https://opencode.ai/install | bash`. **Review**.
  - `apps/utilities/tsui.sh:9` — `curl -fsSL https://neuralink.com/tsui/install.sh | bash`. **Review** (vendor unknown-ish host).
- **`preinstall.sh:45,48,58,65` / `postinstall.sh:101-160` / `install.sh:134-239`** — `sudo apt`, `sudo systemctl`, `sudo install`, `git clone`. Constant/static targets. **SAFE** (interactive bootstrap).
- **`bin/pos-network-scan:88,99`** — `sudo -n nmap` / `sudo nmap`; constant. **SAFE**.
- **`bin/pos-network-hotspot:60-86`** — `sudo create_ap` with `"$@"` passthrough. CLI args reach sudo. **REVIEW** (interactive tool; operator supplies args).
- **`bin/pos-system-backup:173`** — `sudo tar -czvf "$ARCHIVE" -C "$(dirname "$FOLDER")" "$NAME"`; `$FOLDER` CLI arg baked into `$ARCHIVE` name. **REVIEW** (folder name into tar; low risk, arbitrary path backup).
- **`bin/pos-share-nfs-client/smb-client`, `lib/usb-lib.sh`, `lib/share-lib.sh`** — `sudo mount`/`umount`/`mkdir` with mount paths; mountpoint paths validated to be absolute and non-system (smb-client `ask_new_mountpoint`/`menu_ask_mountpoint:579,614` deny `/etc,/boot,/bin,...`). **SAFE/REVIEW** — some paths from `findmnt`/menu.
- **`bin/pos-docker-vbox:1074,1094,1096`** — `docker exec -it ... bash` (interactive attach). **SAFE/DESIGNED-INTERACTIVE**.
- **`scripts/lint-conventions.sh`, `make gen` pipeline** — dev-time `bash -n`/`awk`/`sed`. Out of runtime scope (dev tooling, constant). **SAFE**.
- **No `sshpass`, `scp`, or `ssh` remote-command execution** anywhere (only `pos ssh load-keys` adding keys to the agent, and doc references). No remote-shell-over-ssh primitive found. **N/A**.
- **`lib/scheduler-lib.sh:180`** — `bash -c "$JOB_COMMAND"`; `JOB_COMMAND` is the literal remainder of a `schedule.d/*.env` line, operator-authored, syntax-checked (POS tool). **SAFE/DESIGNED-INTERACTIVE** (operator-owned config; would be RCE if an attacker could write `schedule.d/`).

### Secret-in-process-argv (gpg/openssl)

- **`bin/pos-system-backup:195`** — `gpg --passphrase "$PASS" --symmetric ...`: the backup passphrase is placed on the gpg **command line**, visible to any local user/process via `/proc/<pid>/cmdline` and to `ps as`. **See Section 3.**

---

## 2. Authorization Model — Telegram + Matrix

### Telegram listener (`bin/pos-communication-telegram-listener`)

**Config keys read (via `load_config` line 86-99, plus direct grep in `ai_bridge_prefix`:625):**
| Key | Defined in | Purpose in listener |
|-----|-----------|---------------------|
| `TELEGRAM_BOT_TOKEN` | `# POS_CONFIG:` in `telegram-sender:6`; `telegram.env` | authenticate Bot API |
| `TELEGRAM_CHAT_ID` | same | **the only owner filter** (see below) |
| `TELEGRAM_AI_PREFIX` | same | AI bridge trigger word (default `ai`) |

There is **no** `TELEGRAM_OWNER`, `TELEGRAM_USER_ID`, `TELEGRAM_ALLOWED`, `OWNER_ID`, or any sender-identity allowlist key anywhere in the codebase, config templates, or docs.

**Message flow & the update loop (lines 766-792):**
1. `getUpdates` with `allowed_updates=["message"]` (line 771) — filters update *type* to messages only.
2. Per update: extracts `chat` (`.message.chat.id`), `from_id` (`.message.from.id`), `text` (line 780-783).
3. **The ONLY authorization gate is line 787:**
   ```
   if [ -n "$chat" ] && [ "$chat" != "$TELEGRAM_CHAT_ID" ] && [ "$from_id" != "$TELEGRAM_CHAT_ID" ]; then continue; fi
   ```
   This is: **continue (drop) ONLY IF** chat is set AND chat ≠ owner-chat **AND** from_id ≠ owner-chat.
4. `handle_message` (line 674) then dispatches with **no further sender check**: `/command` map (via `map_get`, line 743) → `run_and_reply` → `bash -c` (C08); web-URL detection → `pos media grab` (line 704); prefix bridge (line 697) → `bash -c`; AI bridge (line 734) → `pos ai gemini ask`.

**Verdict — Telegram does NOT implement "sender authorized AND chat authorized":**
- The check is **chat-or-sender OR**, not AND, and the "sender" comparison uses **`from_id` == `TELEGRAM_CHAT_ID`** — i.e. it assumes the owner's Telegram *user id* numerically equals the *chat id*. That is only true for a direct (1:1) private chat with the owner. In a **group or supergroup**, the `chat.id` is negative and differs from any `from.id`; the OR-clause then accepts **any** `from_id` that happens to equal `TELEGRAM_CHAT_ID` (unlikely) OR requires chat==owner. In a **shared/followup private chat** scenarios or when `TELEGRAM_CHAT_ID` is a forwarded context, the model breaks.
- **Concretely exploitable:** if the bot's token is added to a group, `chat.id` (group, negative) ≠ `TELEGRAM_CHAT_ID` AND `from_id` (a member) ≠ `TELEGRAM_CHAT_ID` → condition **false** → message is dropped. So plain group members are blocked **only if** `TELEGRAM_CHAT_ID` is truly the owner's 1:1 chat and the bot isn't also filtering otherwise. BUT there is **no sender allowlist**, so the guard is the sole mechanism and it mis-handles the general case. If the owner ever sets `TELEGRAM_CHAT_ID` to a group id (a plausible misconfiguration the tool doesn't prevent), **anyone in that group executes commands**. Also the model treats `from_id == TELEGRAM_CHAT_ID` as allowed even when `chat` is different — so a message where sender id coincidentally equals the configured numeric id (or a bot re-post) is accepted regardless of chat.
- **No `from.username`, no `from.first_name/last_name` allowlist, no user-id allowlist** — the requirement "is the SENDER's from.id checked ANYWHERE before a mapped command or AI bridge executes?" is answered: **yes, but only against the chat-id value via an OR with chat-id, and only for one numeric field.** This is not a proper sender authorization.
- **Missing/invalid config behavior:** `run_daemon:759-760` `err`s (exits) if token or chat-id are unset. Good fail-closed for *chat* but there is no sender config to miss.

**Map-file editing surface:** exclusively the **interactive TUI** (`ui()` at line 440, no-arg invocation; `ui_add/ui_edit/ui_remove/ui_test`, lines 378-438) and the `prefix` verb for the prefix map (`prefix_cmd:567`). No network/API path writes `telegram_commands.env`. The map file is `chmod 600` (`map_set:137,144`). **Risk:** it is a **local** file `~/.config/linux_post_install/telegram_commands.env` editable only by the owner at the shell; if the owner account is compromised the map is trivially editable (but that's full-host compromise anyway). The `/cmd::description=` text (user-typed description) flows into `sync_bot_commands` → `setMyCommands` (line 215), so a map *description* is sent to Telegram — a low-level info leak of the operator's own design, not an attacker surface.

### Matrix listener (`bin/pos-communication-matrix-listener`)

**Config keys read (via `load_config`:65-78):**
| Key | Defined in | Purpose |
|-----|-----------|---------|
| `MATRIX_HOMESERVER` | `# POS_CONFIG:` `matrix-sender:5`; `matrix.env` | server URL for /sync |
| `MATRIX_ACCESS_TOKEN` | same | auth |
| `MATRIX_USER_ID` | same | **owner/sender filter** |
| `MATRIX_ROOM_ID` | same | **room filter** (optional) |

**Message flow & /sync loop (lines 509-557):**
1. Resolves owner: `MATRIX_USER_ID` if set, else live `/account/whoami` (lines 514-523).
2. `room_only="${MATRIX_ROOM_ID:-}"` (line 515) — **empty = watch every join.**
3. Per room: skip if `room_only` set and `room != room_only` (line 539).
4. Per event: require `type==m.room.message`, `content.msgtype==m.text` (546-547); **sender filter line 550:** `[ "$sender" = "$owner" ] || continue` — message REFUSED unless the sender is the owner.
5. `handle_message` (line 447) dispatches with **no further sender check**: `/`/`!` command map (line 483) → `bash -c` (C10); `ai ` bridge (line 472) → `pos ai gemini ask`.

**Verdict — Matrix:**
- `MATRIX_ROOM_ID` set: **sender authorized (== owner) AND chat authorized (== configured room)** — matches the requirement. ✅
- `MATRIX_ROOM_ID` unset but `MATRIX_USER_ID` set: sender authorized, chat = **every joined room** — chat is NOT pinned. An owner tweet from any room triggers RCE. ⚠️
- Both unset: owner auto-resolved via whoami (still "sender == owner"), room = every room. Still sender-gated, but the room is unbounded. If `whoami` *fails* (line 520-521), it `err`s out (fail-closed). So Matrix is **sender-gated always** (owner == account's own user id), chat optionally restricted. This is a materially **stronger and correct** model than Telegram's.

**Guard lines that would need to change to satisfy "user AND chat authorized" fully:**
- **Telegram:** replace the OR at `bin/pos-communication-telegram-listener:787` with an AND requiring `chat == TELEGRAM_CHAT_ID` **and** a sender check against a new allowlist key (e.g. `TELEGRAM_OWNER_ID`). Minimal sketch:
  ```bash
  # 1) Chat must be the owner chat
  [ "$chat" = "$TELEGRAM_CHAT_ID" ] || continue
  # 2) Sender must be an allowed user id (new key, fail-closed if unset)
  [ -n "${TELEGRAM_OWNER_ID:-}" ] || { warn "no TELEGRAM_OWNER_ID — refusing"; continue; }
  case " $TELEGRAM_OWNER_ID " in *" $from_id "*) ;; *) continue ;; esac
  ```
  plus add the `TELEGRAM_OWNER_ID` key to the `# POS_CONFIG:` registry in `telegram-sender:6` (`pos config telegram`). **Do NOT implement — this is exploration output only.**
- **Matrix:** to fully pin chat even when `MATRIX_ROOM_ID` is unset, `run_daemon` should fail-closed (refuse to start) or require a room list; currently line 515 defaults to "watch all." Add validation that `MATRIX_ROOM_ID` is set before `--run` (or an explicit allowlist). **Do NOT implement.**

### Other listener/plugin paths that execute commands
- **Entertainment plugins** (`entertainment/{weather,joke,gold}.sh`) fetch public APIs and print text — **no command execution**; output is sent via `pos-entertainment-send` → `notify_send`. Not an RCE surface via chat; they run on a schedule or explicit `pos entertainment send`.
- **`pos-docker-vbox enter`** (`docker exec -it bash`) is operator-attach only.
- **No other chat→command executor** found besides the two listeners and the AI bridge.

---

## 3. Backup / GPG Secret Handling

File: `bin/pos-system-backup`. **PASS provenance chain:**
1. **Prompted interactively** (lines 183-186): `read -s -rp "Enter backup password:" PASS`, then `read -s -rp "Confirm..." CONFIRM`. Read from the terminal with echo suppressed — **not** from config file, env, or argv. Good.
2. Validation (187-191): non-empty and `PASS == CONFIRM`, else loops.
3. `unset CONFIRM` (192) immediately after.
4. **Every place PASS is used:**
   - line 195: `gpg --batch --yes --passphrase "$PASS" --symmetric --cipher-algo AES256 "$ARCHIVE"` — **PASS on the command line** → visible in `/proc/<pid>/cmdline` and `ps` output of `gpg`. **This is the exposure.**
   - line 202: `gpg --batch --quiet --passphrase "$PASS" --decrypt "$ARCHIVE" | tar -tzf -` — verify/decrypt path, **same argv exposure**.
   - line 204: `unset PASS`.
5. **Temp files:** none created for the secret. `mktemp` is **not** used anywhere in backup; the archive is `tar -czvf "$ARCHIVE"` (line 173), then encrypted, then `rm -f "$ARCHIVE"` (line 197) leaving `$ARCHIVE.gpg`, `chmod 600` (line 199). The plain intermediate `.tar.gz` is removed **after** encryption. On **failure** (encrypt/verify fail → `set -euo pipefail` aborts): if gpg fails at 195, the plain `$ARCHIVE.tar.gz` **remains on disk** (sleeped only after the successful encrypt at 197). No trap removes the plain intermediate. This is a **partial-failure plaintext-leak** risk (archive stays unencrypted if `gpg --symmetric` fails). Also the top trap (line 17) sends `notify_send "Backup FAILED..."` on any ERR — does not leak PASS but does announce paths.
6. **verify/decrypt path:** line 202 pipes gpg decrypt into `tar -tzf -` and discards (no plaintext written to disk) — good, verify is streaming.
7. **notify/msg exposure:** backup success sends `notify_send "Backup completed: $ARCHIVE"` (line 211) and USB copy sends `...: $dest` (line 112) — **artifact paths (not contents) are sent to Telegram/Matrix** via `lib/notify.sh`. These are local absolute paths; harmless unless they reveal structure the owner wants private. The **gpg passphrase is NOT** in any notify message.
8. **Shell-history/log exposure:** PASS is read via `read -s` (not echo'd, not in history). It appears only in the gpg argv; not logged to any file by `pos`. However if the operator runs the tool under `set -x` or with shell tracing, `PASS` is a shell variable and would be expanded into stderr; not a repo bug, but the argv placement (not env) is the primary leak vector.

**Other secrets in process argv repo-wide:**
- `bin/pos-network-hotspot:60` — `sudo create_ap ... "$@"`; if a passphrase/SSID is passed as an arg it enters `create_ap` argv. Interactive, no secret stored.
- `matrix-sender` `login` (pos-communication-matrix-sender:167-190): password read via `read -rsp ... </dev/tty`, sent **in the HTTP JSON body** (not argv), access token saved to `matrix.env` `chmod 600` (save_config:67). **Good** — no argv leak.
- `pos-share-smb-client` `make_creds` (143-152): password `read -rsp`, written to a throwaway `mktemp` file `chmod 600`, `printf '...password=%s'` — **not argv**. SMB persistent creds `sudo install -m 600` to `/etc/samba/credentials/` (line 346). **Good**.
- `pos-ai` API keys: sent as HTTP header `x-goog-api-key: ${AI_API_KEY}` (gemini.sh:25) — **not argv**. `AI_API_KEY`/`AI_GEMINI_API_KEY` exported env var; safe.
- Telegram bot token: used in URL `.../bot${TELEGRAM_BOT_TOKEN}/...` (listener:636,768; sender:81) — appears in **URLs/argv of curl** (`curl ... https://api.telegram.org/bot<TOKEN>/...`). The token is in curl's argv → visible via `ps`. **This is a real secondary exposure**: the Telegram bot token is a local-process-argv secret. Same class as the gpg passphrase.

---

## Severity-ranked concrete vulnerabilities (real, not hypothetical)

**V1 — HIGH — Telegram listener lacks sender authorization; remote code execution as your user.**
`bin/pos-communication-telegram-listener:787` is the only gate and it is an OR over `chat`/`from_id` against the single `TELEGRAM_CHAT_ID` value, with **no sender allowlist key existing anywhere**. Any message that satisfies either `chat == TELEGRAM_CHAT_ID` OR `from_id == TELEGRAM_CHAT_ID` triggers mapped `bash -c` (C08) and the Gemini bridge. In group/shared-chat misconfiguration, any member runs arbitrary commands as the owner. Even in the "correct" 1:1 setup there is no authenticated-sender binding, so a bot-repost or replayed `from_id` is accepted regardless of source chat. Evidence: lines 787, 743, 697, 734.

**V2 — HIGH — `pos ai` evaluates arbitrary AI-provider output; `--trust` removes confirmation.**
`bin/pos-ai:388,403` runs `eval "$cmd"` where `$cmd` is extracted from the provider's raw response (`_extract_commands`:363). The Telegram/Matrix AI bridges (listener:734/:472 / C14/C15) feed arbitrary chat text as the prompt; if the model's reply (or a prompt-injection / model misbehavior) emits a fenced `bash`/`sh` block, it is executed. Non-trust mode prompts on a tty (`[ -w /dev/tty ]`), but **trusted aliases** pass `--trust` (`TRUST_MODE=1`, :385-388) → auto-execute, no confirm. And the **AI bridges run non-interactively (no tty)**, so `_prompt_run_command`'s `[ -w /dev/tty ] || return 0` at line 382 returns 0 **without prompting** → **any** command block in a bridge-AI reply executes automatically even without trust. This makes the chat AI bridge an unconditional RCE on model output. Evidence: pos-ai:382,388,403,535,572; listeners:734/:472.

**V3 — HIGH — backup GPG passphrase on command line (argv exposure).**
`bin/pos-system-backup:195,202` pass `--passphrase "$PASS"` to gpg → secret readable by any local user or leak to syslog/ps. Evidence: lines 195, 202. (Also the plain `.tar.gz` can remain on a failed encrypt: line 197 is only reached after a successful 195.)

**V4 — MEDIUM — Matrix listener optional chat authorization.**
When `MATRIX_ROOM_ID` is unset (default), `run_daemon:515` watches **all joined rooms**; sender still must equal the owner (`:550`), so it's owner-only but unbounded-room. If the account is in any shared room and the owner sends a command there, it executes. Fails closed on unresolved owner (`:521`), so severity is bounded to owner-initiated events. The authorization model is *correct* conceptually but chat-scope defaults too broadly.

**V5 — MEDIUM — unvalidated host/port interpolated into `bash -c /dev/tcp` strings.**
`bin/pos-network-checkport:133,157,166,168`, `bin/pos-share-smb-client:92`, `lib/share-lib.sh:59`. Host strings are not fully validated (no `;`/`$()`/backtick reject) before being embedded in a shell string. Reachable via CLI args (interactive) and `NET_PROBE` env (`pos-network-download:28,377`).

**V6 — LOW/MEDIUM — `curl | sh` / `curl | sudo bash` installers without checksums.**
`apps/{zerotier,netbird,tailscale,docker,opencode,tsui}.sh`. Vendor-standard, but supply-chain risk from the remote script. Interactive install-time only.

**V7 — LOW — Telegram bot token in curl argv.**
`bin/pos-communication-telegram-listener:636,768` and `telegram-sender:81` place `bot<TOKEN>` in a URL passed to curl → token visible in `/proc/<pid>/cmdline`. Same class as V3.

---

## Uncertainties / Could-not-verify

- **Exact live behavior of the Telegram `from_id`/`chat_id` equality in real groups** cannot be established by read-only inspection; the numeric-equality assumption is documented in the code (line 787) but its breakage requires a live group test. This is the crux of V1's real-world exploitability and needs a live check by another agent.
- **Whether `ps`/`/proc` argv is considered a real threat model** for this homelab (single-user local machine) is a policy/rationale question the Explorer can't decide — see note in V3.
- **`pos-network-download`'s `NET_PROBE`** default is constant; whether any deployment injects an attacker-controlled value is unknown — it honours an env var seam.
- **Whether any operator already sets a `MATRIX_ROOM_ID`** (affects V4) is config state not present in the repo (config files are gitignored).
- The exact content of runtime `telegram_commands.env` / `matrix_commands.env` map files (what commands are mapped) is unknown — gitignored.

---

## Important Files
- `bin/pos-communication-telegram-listener` — auth gate (787), dispatch, AI/prefix bridges.
- `bin/pos-communication-matrix-listener` — owner filter (550), room gate (539).
- `bin/pos-ai` — eval path (388,403,382), trusted mode, bridge call sites.
- `bin/pos-system-backup` — passphrase argv usage (195,202).
- `bin/pos-network-checkport`, `bin/pos-share-smb-client`, `lib/share-lib.sh`, `bin/pos-network-download` — /dev/tcp interpolation.
- `lib/ai-providers/gemini.sh` — API key in HTTP header (not argv).
- `bin/pos-communication-{telegram,matrix}-sender` — POS_CONFIG registry, token/creds handling.
- `lib/notify.sh` — artifact-path-only notify sends.

---

## Handoff

- **Status:** COMPLETE (investigation objective satisfied; no code changed).
- **Objective:** Security audit of command-execution surfaces, chat authorization, secret handling.
- **Evidence:** file:line citations throughout; classification by certainty (SAFE / DESIGNED-INTERACTIVE / VULNERABLE-INPUT / REVIEW) with provenance chains.
- **Affected areas:** Telegram & Matrix listeners, `pos-ai` eval, backup GPG, /dev/tcp probes, installer curl|sh.
- **Scope/decision boundary:** Read-only exploration only; **no changes proposed for implementation.** Minimal change sketch for the Telegram auth gate is provided at Section 2 (as exploration output, explicitly NOT implemented).
- **Verification performed:** Full source tracing of both listeners, pos-ai eval, backup, notify, and all grep'd primitives; git blame on the Telegram gate (unchanged since 2026-08-06, b9edd078 / 014d6be).
- **Remaining uncertainty:** live Telegram group behavior (V1), NET_PROBE env deploy state, MATRIX_ROOM_ID config state, real `ps`-argv threat model.
- **Recommended next agent:** **Architect** — the two listeners embody two different authorization philosophies (Telegram: chat-id-OR, no sender allowlist; Matrix: owner-sender with optional room). Aligning them into one "sender AND chat authorized" contract is a cross-component design decision (config schema + registry keys + both daemons), which is precisely an architectural boundary. Evidence above gives the exact guard lines and a minimal-change sketch to evaluate, not implement.

### Scope-expansion note
Investigating Telegram/Matrix authorization surfaced that the auth contract is **not a single-file bug** but a **cross-component, decision-level** matter (two daemons, the `# POS_CONFIG:` registry, config templates, docs, and a new `TELEGRAM_OWNER_ID`-style key). That is an architectural decision, so the handoff above goes to **Architect** per the Explorer's scope rule.

```text
Status: COMPLETE (with Architect handoff on scope expansion)
Reason: Fixing chat authorization correctly spans two listeners + config schema + registry + docs
Evidence: listener auth gates telegram:787 / matrix:550,539; POS_CONFIG headers in senders; no owner key anywhere
Affected areas: bin/pos-communication-telegram-listener, matrix-listener, telegram-sender (POS_CONFIG), config templates, DOC
Decision required: Architect
Out-of-scope changes: none
```
