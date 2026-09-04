# Designer spec — `pos docker vbox` CREATE: categorized selection flow

Date: 2026-08-23 · Author: Designer · Status: IN PROGRESS

## TL;DR
- Status: DESIGN_READY (provisional on 3 open questions, see §9).
- Redesign: interactive create becomes **Name → Category hub → per-category baskets → Review & create**; the scripted `create` verb stays the single execution path and gains additive flags (`--device --gpu --port --cpus --memory --network`, repeatable `--dir`). Zero-flag invocations stay byte-compatible.
- Multi-select = loop-of-single-picks basket pattern (menu_pick wrapped in a shell loop). No lib/menu-lib.sh changes.
- Categories: GPU/Nvidia + Host devices + Host dir mounts (**MUST**, user-requested); Image/disto quick-picks + Resources(cpu/mem) + Ports (**SHOULD**); Network mode + Env/raw-args (**OPTIONAL v2**).
- Nvidia: 3 graceful paths (toolkit→`--gpus all` recommended / nodes-without-toolkit→explicit `--device` trio / none→info line, manual escape hatch). CUDA image only ever a `[i] tip:` hint.
- EOF anywhere = discard, nothing created (fail-closed, repo convention). Review 'n' → hub with edits preserved.

---

## 0. Grounding (evidence)

- `bin/pos-docker-vbox:73-86` — today's interactive create: name → image(default `ubuntu:22.04`) → dir prompts via `menu_ask_value`, then `confirm … n`, then `menu_self create`.
- `bin/pos-docker-vbox:159-212` — scripted `create <name> [image] [--dir <path>]`: label `linux_post_install.vbox=true`, `-v "$lab_dir:$lab_dir"` (same-path convention), `-w`, `docker create -it … bash`, optional `Enter now?` tail.
- `lib/menu-lib.sh` — `menu_run` (numbered loop, rc1 on 0/q/Q/EOF), `menu_pick` (type-to-filter, fixed suffix `[1-N], text=filter, 0=back`, rc1 on 0/q/b/EOF), `menu_ask_value` (rc1 EOF / empty-no-default), `menu_guard`. All stderr-rendered, fail-closed, never exit.
- `lib/common.sh:120` `confirm` — y-only default when invoked as `confirm "…" n`; bash `read` on EOF returns falsy ⇒ deny. Fail-closed.
- Detection sources available per brief: lsusb(+`/dev/bus/usb/B/D`), lspci(VGA/3D)+`/dev/nvidia* /dev/nvidiactl /dev/nvidia-uvm`, `/dev/ttyUSB* /dev/ttyACM* /dev/video* /dev/snd/*`, lsblk, host dirs. Toolkit probe: `docker info --format '{{json .Runtimes}}'` contains `nvidia`.

---

## 1. Flow map

```
run_menu ("Create a VM")
  └─ menu_vbox_create                      [REDESIGNED — tty-only, unchanged trigger]
       1) menu_ask_value "VM name"          ← the ONE flat prompt kept (identity first;
       │                                      empty/EOF ⇒ back to main menu, nothing created)
       2) CATEGORY HUB  (menu_run, live basket counts in labels)   ── loop ──┐
       │    0/q ⇒ confirm-discard (default n) ⇒ main menu                    │
       3) per category: picker/prompt → basket mutate → back to hub ──────────┘
       4) "Review & create" → summary box → confirm "Create? [y/N]"
            y ⇒ menu_self create <name> <image> <composed flags…>   (existing verb)
            n ⇒ back to CATEGORY HUB (edits preserved)
            EOF ⇒ discard all, "[!] setup discarded — nothing was created", main menu

Scripted/non-tty path (UNCHANGED entry point):
  pos docker vbox create lab1 kali --dir .            → exactly today's behavior
  pos docker vbox create lab1 --gpu --device /dev/ttyUSB0 --port 8080:80 …
      → new ADDITIVE optional flags parsed by the same verb; absence of every new
        flag reproduces current output byte-for-byte (same echos, same docker argv).
```

Rules:
- The categorized UI exists ONLY inside `menu_vbox_create` behind the existing tty gate (`run_menu` is already opt-in/tty-gated at `pos-docker-vbox:134-141`). Non-tty stdin can never reach it.
- Menu remains pure sugar: it composes arguments and re-enters the scripted verb (`menu_self create …`) — one execution path, matching the tool's own header comment (`:44-48`).
- Name collision guard stays in the verb (`container_exists`, `:181`).

---

## 2. Category list

Hub item labels carry live state (see §3). Order = user mental model: *what runs → what it can touch → how reachable → limits*.

| # | Category | Priority | Data source | Maps to |
|---|----------|----------|-------------|---------|
| 1 | Image & distro | **SHOULD** | curated quick-pick list + free text | positional `<image>` (default `ubuntu:22.04` if never visited) |
| 2 | GPU / Nvidia | **MUST** (user req #1) | `/dev/nvidiactl` node scan + `docker info` runtimes | `--gpus all` **or** explicit `--device /dev/nvidia0 --device /dev/nvidiactl --device /dev/nvidia-uvm` |
| 3 | Host devices | **MUST** (user req #2) | lsusb→usb nodes; ttyUSB/ttyACM/video/snd globs; lsblk; manual path | repeatable `--device <node>` |
| 4 | Host dir mounts | **MUST** (user req: mounts implied by "and more"; core vbox concept) | typed host paths (validated `-d`) | repeatable `-v <host>:<host>` (same-path convention, matches verb `:202`) |
| 5 | Ports publish | **SHOULD** | typed `HOST:CONTAINER` pairs | repeatable `-p H:C` |
| 6 | CPU / RAM | **SHOULD** | typed values, empty = Docker defaults | `--cpus N`, `--memory SIZE` |
| 7 | Network mode | **OPTIONAL v2** | radio pick | `--network bridge\|host\|none` |
| 8 | Env vars / raw extra args | **OPTIONAL v2** | typed KEY=VAL / raw string | `-e K=V` repeats / trailing raw args |

Quick-pick image list (SHOULD): `ubuntu:22.04`, `ubuntu:24.04`, `debian:12`, `kalilinux/kali-rolling`, `archlinux`, `fedora:latest`, `alpine:latest` + `Other (type image ref)`. When GPU configured and chosen image is a plain distro, show one-line `[i] tip: for CUDA inside the VM try an image like nvidia/cuda:12.4-base-ubuntu22.04 (set it under Image & distro)` — hint only, never auto-applied.

Out of scope for v1 even if detection could support it: X11/Wayland display forwarding, `/dev/snd` fine-grained node picks (offer `/dev/snd` as one entry), hotplug watching, profiles/persistence.

---

## 3. Interaction mechanics per category

**Hub (category menu)** — `menu_run` titled `Configure VM 'lab1' — capabilities`. Items re-render each loop with state:

```
════════════════════════════════════════════
  Configure VM 'lab1' — capabilities
════════════════════════════════════════════
  1) Image & distro ....... ubuntu:22.04 (default)
  2) GPU / Nvidia ......... not configured
  3) Host devices ......... 2 selected
  4) Host dir mounts ...... ~/lab1 (auto) + 1 more
  5) Ports ................ none
  6) CPU / RAM ............ Docker defaults
  7) Review & create
  0) Exit
----------------------------------------
```
- Hub `0`/`q` (menu_run rc1): `confirm "Discard this VM setup?" n` — y ⇒ main menu; n ⇒ redraw hub. Protects reflexive exits from losing a long basket.
- Every category accepts re-entry; single-value categories (Image, GPU, Resources, Network) pre-show current value and replace on change. Basket categories (Devices, Mounts, Ports) open an add/remove submenu (below).
- Each mutation prints immediate `[+]` feedback line (house style).

**Basket categories — shared add/remove/clear shape**
On entry with non-empty basket:
```
 1) Add …
 2) Remove one (2 selected)
 3) Clear all
 0) Back
```
Empty basket skips straight to the add loop.

**Image & distro**: `menu_pick "Pick image"` over quick-picks (+ `Other` pseudo-item last → `menu_ask_value "Image ref"`). Replace semantics. Validation: reject whitespace in refs (`[!] not a valid image ref — spaces not allowed`).

**GPU / Nvidia** (details §5): dynamic `menu_run` of mode options; single-choice; current mode marked `(current)`; option `none/back` clears GPU basket.

**Host devices**: candidates computed once per category-entry (fresh snapshot, cheap commands only). Add-loop = `menu_pick` over candidates **not already selected** + trailing pseudo-items:
```
 98) Type a device path manually
 99) ✓ Done adding
```
After each add: `[+] added /dev/ttyUSB0` and loop redraws with updated `Selected so far: …` header. Remove = `menu_pick` over basket. Clear-all = `confirm "Remove all N device(s)?" n`.

**Host dir mounts**: add-loop = `menu_ask_value "Host directory to mount (empty = done)"`. Validate: nonexistent ⇒ `[!] directory not found: /x — try again`; empty input ends loop. Container side defaults to same path; after accept print `[+] will mount /x:/x`. Remove/Clear via shared shape.

**Ports**: add-loop = `menu_ask_value "Publish port HOST:CONTAINER (empty = done)"`. Validate `^[0-9]+(:[0-9]+){1,2}$` (allow `HOST:CT` and `HOSTIP:H:C` later; v1 = simple pairs). Duplicate host port ⇒ `[!] host port 8080 already mapped — rejected`. `[+] will publish 8080:80`.

**CPU/RAM**: two `menu_ask_value` with NO value-defaults but `[i] press Enter to keep Docker defaults` shown first. Validate cpus: `^[0-9]+(\.[0-9]+)?$`; mem: `^[0-9]+(b|k|m|g|mb|gb)?$` case-insensitive. Invalid ⇒ warn + reprompt (never abort flow).

**Network (v2)**: `menu_run` radio `bridge (default) / host / none`.

**EOF semantics (binding everywhere)**: EOF at ANY depth (name prompt, hub, picker mid-basket, ask_value, summary confirm) behaves like answering "no": print `[!] setup discarded — nothing was created`, return to main vbox menu loop, exit code clean (matches `|| return 0` idiom at `:75-107`). A partially-filled basket is never silently committed.

---

## 4. Multi-select mechanics (no lib changes)

Pattern: **loop-of-single-picks basket**. `menu_pick`/`menu_run` stay untouched; a wrapper loop owns the basket array and the wording around them.

Canonical add-loop (pseudocode contract for Builder):

```
loop:
  header (stderr): "Devices — selected: N" + comma list or "(none yet)"
  items = unselected candidates + [Type manually] + [✓ Done]
  choice = menu_pick "Pick device to ADD" items…
    rc1 (0/b/EOF) ⇒ treat as Done (basket kept)   ← picker's own back also ends loop
    pick candidate ⇒ dedupe-guard (skip-if-present, shouldn't occur since excluded),
                     append, echo "[+] added <item>"
    pick "Type manually" ⇒ menu_ask_value "Device path (/dev/…)";
         must match ^/dev/; duplicate vs basket ⇒ "[!] already selected — skipped"
    pick "Done" ⇒ leave category
after each add, loop continues until Done/back — the hint the user reads is:
```

Exact user-visible strings (Builder MUST use verbatim):

| Moment | String |
|---|---|
| Picker prompt | `Pick device to ADD [1-M], text=filter, 0=back ` (suffix fixed by menu_pick) |
| After add | `[+] added /dev/ttyUSB0 — pick another, or choose ✓ Done` |
| Manual entry label | `Device path (must start with /dev/, empty = cancel)` |
| Duplicate | `[!] /dev/video0 is already selected — skipped` |
| Remove prompt | `Remove which device? [1-N], text=filter, 0=back ` |
| After remove | `[+] removed /dev/video0` |
| Clear confirm | `Remove all N selected device(s)? [y/N]` |

Same skeleton reused for mounts (`Add mount directory…`) and ports (`Publish port…`), with their validators swapped in. This satisfies multi-select without any `menu-lib.sh` primitive addition (lib change explicitly out of scope; if a native multiselect is ever wanted, that's a separate lib-design decision).

---

## 5. Nvidia specifics

Detection (cheap-first, run once per GPU-category entry):

```
nodes    = ls /dev/nvidiactl present?  (sanity anchor) ; collect /dev/nvidia[0-9]+ , nvidia-uvm
toolkit  = docker info --format '{{json .Runtimes}}' mentions "nvidia"
           (fallback: command -v nvidia-container-runtime || command -v nvidia-container-ctk)
gpu_pci  = lspci | grep -Ei 'vga|3d controller' | grep -i nvidia   (context line only)
```

Three graceful paths:

| Path | Condition | UX |
|---|---|---|
| **A — full support** | nodes ∧ toolkit | menu: `1) Full GPU access (--gpus all)  (recommended)` · `2) Explicit Nvidia device nodes` · `0) none`. Path A default highlight = recommendation, not preselection. |
| **B — nodes, no toolkit** | nodes ∧ ¬toolkit | info line first: `[i] nvidia-container-toolkit not detected — --gpus all will likely fail; offering explicit device nodes instead (install nvidia-container-toolkit for CUDA workloads)`. Menu offers explicit-nodes mode + `configure anyway (--gpus all)` escape. |
| **C — no GPU found** | ¬nvidiactl | `[i] no Nvidia driver/GPU detected on this host — skipping GPU setup`. Category still enterable (shows the info + manual `/dev/…` entry for exotic setups), otherwise back. Never an error, never blocks create. |

Explicit-nodes mode: `menu_pick` over discovered nodes (labels like `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-uvm`) with select-all-default suggestion `[i] a working set is usually nvidia0 + nvidiactl + nvidia-uvm`; plus manual path entry. Compose as repeated `--device` (works without toolkit).

Permission nuance (edge case, binding): device-node readability is judged by **dockerd (root), not our uid** — do NOT filter candidates by our own access bits. Only drop entries that fail `stat` entirely. If our read fails but stat succeeds, append label ` (perm-restricted for you — dockerd may still access)`.

CUDA image hint: OPTIONAL, one line, only when gpu_mode ≠ none AND image looks like a plain distro — wording in §2. Never forced, never mutates the basket.

---

## 6. Summary + confirm screen

Rendered to stderr right before `menu_self create`:

```
════════════════════════════════════════════
  Create VM 'lab1' — review plan
════════════════════════════════════════════
  image      ubuntu:22.04
  host dir   ~/lab1  (bind-mounted at same path, cwd inside VM)
  gpus       --gpus all
  devices    --device /dev/ttyUSB0
             --device /dev/bus/usb/001/004
  mounts     /mnt/data:/mnt/data
  ports      -p 8080:80
  cpu/ram    Docker defaults
  network    Docker default (bridge)
----------------------------------------
  docker create -it --name lab1 --label linux_post_install.vbox=true \
      --gpus all --device /dev/ttyUSB0 … ubuntu:22.04 bash
```
- Every configured row shows its literal docker-flag rendering; unset rows show their default in words. Long lists truncate visually at ~6 rows with `… (+N more)` (full plan visible in the composed-command footer).
- Single binary confirm: `Create? [y/N]` (default-deny).
  - `y` ⇒ hand off to verb; verb's existing output (`[+] Lab directory`, pull, create, `Enter now?` tail) plays unchanged.
  - `n` ⇒ return to **category hub, edits preserved**.
  - EOF ⇒ discard-all per §3 rule.
- The composed command footer doubles as the Builder's own debug aid — keep format stable for the pty probes (§8).

---

## 7. Non-goals v1

- No resource knobs beyond `--cpus/--memory` (no pids-limit, shm-size, ulimits).
- No compose integration, no saved profiles, no cross-session persistence — vboxes are disposable by design (survey wording: "Disposable Docker-based VMs").
- No GUI/display forwarding (X11/Wayland sockets), no audio beyond offering `/dev/snd` as a device entry.
- No USB hotplug monitoring — device list is a snapshot at create time.
- No `lib/menu-lib.sh` changes; no new global primitives.
- No JSON/machine-readable create output; human-readable only.
- No editing of existing containers (create-time only; changing devices = rm + recreate).

---

## 8. Builder handoff checklist

**Files allowed**
- `bin/pos-docker-vbox` — ONLY implementation file. Update its `usage()` heredoc (new flags), `# POS_SUBCMDS` unchanged, consider `# POS_FLAGS:` addition (feeds completions via make gen).
- Docs: `DOC/POS.md` detail block (hand-maintained), root README example block if flags deserve a line. Everything generated: `make gen && make check && make lint` green (definition of done; lint must end `0 FAIL, 0 WARN`).
- NOT allowed: `lib/menu-lib.sh`, `lib/common.sh`, other tools, dispatcher.

**Flag contract (additive, all optional; absence ⇒ byte-identical legacy behavior)**
```
create <name> [image] [--dir <path>]…      (repeatable now)
                   [--device </dev/node>]… [--gpu]           # --gpu ⇒ --gpus all
                   [--port HOST:CONTAINER]… [--cpus N] [--memory SIZE]
                   [--network MODE]                          # v2 may defer
```

**Probe scenarios (pty harness; stub `docker`, `lsusb`, `lspci`, `lsblk`, `nvidia-container-runtime` via PATH shims)**
1. Happy minimal: name → Review → y ⇒ assert docker argv == legacy form.
2. Full basket: image quick-pick + gpu(all) + 2 devices + mount + port ⇒ assert exact composed argv + `[+]` lines sequence.
3. GPU paths A/B/C under three stub sets (toolkit±, nodes±) incl. the three exact info lines.
4. Basket edit: add 3 → remove 1 → clear → re-add ⇒ final argv correct; duplicate manual-entry rejection.
5. EOF injection at EVERY depth (name, hub, mid-add-loop, ask_value, summary) ⇒ nothing created, clean rc, `[!] setup discarded` printed exactly once.
6. Hub `0` → discard-confirm `n` ⇒ back at hub with basket intact (regression for reflexive-exit protection).
7. Non-tty scripted create: legacy invocation golden-output test (byte-compat); new-flags invocation composes correctly; unknown flag ⇒ usage error.
8. Empty detection: no usb/no pci/no nvidia ⇒ categories render "(unavailable)/(none found)" states, flow never stalls.
9. Invalid inputs: bad dir, bad port spec, bad cpu/mem strings ⇒ warn+reprompt loops; flow always recoverable.
10. Perm-restricted node (stat ok, read denied) ⇒ offered with warning label; not filtered.

**Edge cases to encode**
- Empty detection results everywhere (§5 path C, §3 empty-basket skip).
- Permission-denied device nodes: offer, label, don't filter (dockerd is root).
- Duplicates across sources (USB-derived + manual typed same node): dedupe guard with `[!] already selected — skipped`.
- `lsusb`/`lspci` binaries absent ⇒ skip that source silently with one `[i]` line; never error.
- Image ref with spaces ⇒ rejected at Image category.
- Existing container name ⇒ verb's existing guard handles; hub need not pre-check.
- Very long baskets ⇒ summary truncation rule (§6); argv itself untruncated.

---

## 9. Open questions (for Orchestrator/user)

1. Flag spellings OK? Proposed long-only (`--gpu`, `--port`, `--cpus`, `--memory`, `--network`); alternative would be docker-style short aliases — recommend long-only for completion consistency.
2. Keep the verb's post-create `Enter now?` tail when launched from the categorized flow? Assumed YES (unchanged verb tail).
3. Block-device exposure policy: list ALL disks with a `(system disk — careful)` label on mounted ones (recommended), or hide non-removable system disks in v1?

---

## Verification performed by Designer
- Re-read `bin/pos-docker-vbox` (261 ln, post-T4) — located interactive create at :73-86, scripted verb at :159-212, tty gate at :138-141.
- Read `lib/menu-lib.sh` contracts (rc semantics, stderr/stdout split, fail-closed EOF) — basket pattern designed strictly within them.
- Read `common.sh:120-129` confirm — verified default-deny + EOF-denies behavior.
- Skimmed `templates/pos-tool.sh` for house conventions (`[+]` lines, deps guards, docs regen duty).
- No files modified outside `reportAgents/`.

Status: **DESIGN_READY** (provisional pending §9 answers — none of them block Builder starting on §8 scenarios 1, 5, 7).

REPORT_PATH: ./reportAgents/2026-08-23-designer-vbox-create-categories.md
