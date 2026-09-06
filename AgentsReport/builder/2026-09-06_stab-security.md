# Builder report — 2026-09-06 stabilization security track (D-A, V3, V5, V7)

## TL;DR

Status: **IMPLEMENTED** — all approved changes done, gates green, 23/23 probes PASS.
Scope: architect decision D-A (telegram owner gate, matrix fail-closed) + explorer findings V3 (backup gpg argv leak), V5 (/dev/tcp host injection), V7 (documented notice); plus template-creation and two hygiene fixes listed in the brief.
Verified: `bash -n` on all touched scripts, `make gen`, `make check` (check-sync: OK), `make lint` (0 FAIL, 0 WARN), runtime registry smoke (`pos config telegram` scope shows `TELEGRAM_OWNER_ID`), and a 23-assertion probe harness (fail-closed telegram/matrix behavior, gpg fd + cleanup, host-injection attempts) — all PASS.
Files changed: 9 code/doc files in scope, 2 new config templates, plus `DOC/AGENT_Context_Project.md` + `completions/pos.bash` from the required `make gen`.

## Step 1: D-A telegram listener owner gate — [DONE]

- `bin/pos-communication-telegram-listener`: per-message authorization replaced by fail-closed AND-gate: message processed only when `chat == TELEGRAM_CHAT_ID` AND `from_id == TELEGRAM_OWNER_ID`; unauthorized → warn-only, skip (no reply) (`bin/pos-communication-telegram-listener:805`).
- Owner unset → daemon runs but every command is ignored with warn "TELEGRAM_OWNER_ID unset — ignoring command" (`bin/pos-communication-telegram-listener:798`); startup logs "commands authorized" or warns fail-closed; run line now logs owner (`bin/pos-communication-telegram-listener:518-530` region).
- `bin/pos-communication-telegram-sender` registry line gained `TELEGRAM_OWNER_ID=digits:Numeric Telegram user id (your account) allowed to run chat commands`; usage() config block updated.
- Probes 1a–1d prove: owner-unset → warning + no send; right chat+user → executes; wrong user → ignore; wrong chat → ignore. 8/8 PASS.

## Step 2: D-A matrix listener fail-closed — [DONE]

- `bin/pos-communication-matrix-listener`: with `MATRIX_ROOM_ID` unset the daemon runs but shows `room none — fail-closed` and watches NO room; the room filter is now fail-closed (`[ -z "$room_only" ] || [ "$room" != "$room_only" ]`), startup warn at `bin/pos-communication-matrix-listener:519`.
- Probe 2 (owner message, room unset) proves: warning logged, run line shows fail-closed, nothing answered. 3/3 PASS.

## Step 3: Config templates + sender registry — [DONE]

- `config/telegram.env` and `config/matrix.env` created as commented reference templates (config/ai.env style) since no templates existed.
- Verified `postinstall.sh:22-50` copies only explicitly named `entertainment.env/system.env/notify.env/ai.env` (no glob) — templates are NOT auto-installed; runtime provisioning remains `pos config telegram` / `pos config matrix`. Residual gap: postinstall.sh does not copy the new templates (out of scope).

## Step 4: V3 backup gpg passphrase fd — [DONE]

- `bin/pos-system-backup`: both gpg calls use `--passphrase-fd 3` + `3<<<"$PASS"` (`bin/pos-system-backup:197`, `:207`); failed encrypt removes the plaintext archive + err "encryption failed — plaintext archive removed, nothing left behind"; failed verify removes the corrupt `.gpg` + err; `unset PASS` retained.
- Probes: gpg argv has `--passphrase-fd 3`, no `--passphrase <value>`, secret absent from argv/logs; success path leaves only `.gpg` (chmod 600); fail path leaves neither plaintext nor partial artifact, with honest error. 8/8 PASS.

## Step 5: V5 /dev/tcp host injection — [DONE]

- Positional-arg form everywhere a remote host reaches `bash -c 'exec 3<>/dev/tcp/…'`:
  - `bin/pos-network-checkport:135` (check_tcp), `:168`/`:170` (banner probes) — `_ "$ip" "$port"`.
  - `bin/pos-share-smb-client:94` — `_ "$host" "$SMB_PORT"`.
  - `lib/share-lib.sh:61` (share_port_probe, shared core) — `_ "${1}" "${2}"`.
  - `bin/pos-network-download:28` — default `NET_PROBE` now `timeout 3 bash -c 'exec 3<>/dev/tcp/$1/$2' _ 8.8.8.8 53`.
- POS.md NET_PROBE doc updated at line 188 (also fixed pre-existing missing `>` in the doc example).
- Probes: hostile host `8.8.8.8;touch …` passed as ONE literal arg, probe source uses `$1/$2`, no marker file created, hostile connect fails harmlessly; same for `share_port_probe` and smb-client `probe_server`. 8/8 PASS.

## Step 6: V7 notice + doc/hygiene updates — [DONE]

- `DOC/howto/communication.md`: one-time Telegram setup notes `TELEGRAM_OWNER_ID` (set via `pos config telegram`) and the inherent token-in-argv caveat of Bot API URLs (revoke if leaked); owner-only bullet for chat commands; matrix self-messaging bullet.
- POS.md: telegram-listener row (owner id), matrix-listener row (fail-closed), backup row (passphrase on internal fd — never argv), telegram/matrix paragraphs (~372/402).
- Hygiene: `apps/ai/llamacpp.sh` chmod 755 (still untracked); `DOC/APPS.md` line 3 app count 16 → 18.

## Step 7: Gates + probes — [DONE]

- `bash -n` on all 10 touched scripts: OK.
- `make gen` OK (required by POS_CONFIG change; also folded in parallel-track drift), then regeneration re-verified.
- `make check`: OK. `make lint`: 0 FAIL, 0 WARN.
- Probe harness `/tmp/opencode/probe-stab.sh` (23 assertions): **PASS=23 FAIL=0**. Harness uses stub `curl`/`gpg`/`sudo` (secret-free argv assertions), extracted real function bodies verbatim for checkport/smb-client/share-lib, and verifies no marker file is created by hostile hosts.

## Residual risks / follow-up

- `config/telegram.env` / `config/matrix.env` are reference templates only — not wired into `postinstall.sh` (out of scope; installer currently copies only 4 explicit env files).
- Existing deployments without `TELEGRAM_OWNER_ID` / `MATRIX_ROOM_ID` now ignore all chat commands (INTENDED fail-closed; startup warn tells the operator to run `pos config telegram` / `pos config matrix`).
- Matrix-sender unchanged (its registry already listed MATRIX_ROOM_ID).
- Parallel tracks still dirty in git (ai track, app templates, lint-conventions, AGENT_TODO, docs) — not touched here.

## Files changed (this track only)

- `bin/pos-communication-telegram-listener`, `bin/pos-communication-telegram-sender`, `bin/pos-communication-matrix-listener` (D-A)
- `bin/pos-system-backup` (V3)
- `bin/pos-network-checkport`, `bin/pos-share-smb-client`, `lib/share-lib.sh`, `bin/pos-network-download` (V5)
- `config/telegram.env`, `config/matrix.env` (new templates)
- `DOC/POS.md`, `DOC/howto/communication.md`, `DOC/APPS.md` (docs)
- `DOC/AGENT_Context_Project.md`, `completions/pos.bash` (make gen output)
- `apps/ai/llamacpp.sh` (mode 755 only)