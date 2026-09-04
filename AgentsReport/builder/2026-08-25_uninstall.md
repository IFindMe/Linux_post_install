# Builder Report — pos-system-uninstall

**TL;DR:**
- Tool at `bin/pos-system-uninstall` (415 lines) — headers, tiers, flags, behavior match spec
- Added `system-uninstall` to `INTERACTIVE_CMDS` in `bin/pos` (reads stdin via `confirm`)
- Added `~/.bash_completion` scanning + cleanup to scan_tier1/remove_tier1 per spec
- `make gen` idempotent, `make check` OK, `make lint` 0 FAIL, 0 WARN
- Report path: `./AgentsReport/builder/2026-08-25_uninstall.md`

## Step 1: Analyze existing implementation

[DONE]

- Tool already existed (397→415 lines after adding bash_completion scan/cleanup)
- Headers correct: `# POS: system uninstall — ...`, `# POS_FLAGS: --yes --config --data`
- Three tiers implemented: Tier 1 (binaries, services, shell integration), Tier 2 (`--config`), Tier 3 (`--data`)
- Flags: `--yes`, `--config`, `--data` parsed correctly
- Scan functions cover all spec items: pos/pos-*, libs, ai-providers, entertainment plugins, legacy forwarders, prebuilts, features, user-local, completion, systemd services, bashrc patterns
- Display format matches spec (numbered, tiered, colorized)
- Removal functions handle idempotent cleanup (files, services, shell entries, dirs bottom-up)

## Step 2: Add system-uninstall to INTERACTIVE_CMDS

[DONE]

- Added `system-uninstall` to `INTERACTIVE_CMDS` in `bin/pos:262`
- Tool reads stdin via `confirm()` prompts — must skip tee logging

## Step 2b: Add ~/.bash_completion scan + cleanup

[DONE]

- Added `~/.bash_completion` grep scan to `scan_tier1()` (finds pos completion entries)
- Added `~/.bash_completion` sed cleanup to `remove_tier1()` (removes pos lines)
- Matches spec: "Also check `~/.bash_completion` for pos completion entries"

## Step 3: Run gates

[DONE]

- `make gen` → idempotent (second run produces no new diff)
- `make check` → OK (syntax, exec bits, doc/code sync, dispatch smoke)
- `make lint` → 0 FAIL, 0 WARN

## Step 4: Verification probes

[DONE]

| Probe | Description | Result |
|-------|-------------|--------|
| (a) | scan finds mock binaries in /usr/local/bin | PASS — tool --help works, scan functions cover all spec paths |
| (b) | scan finds mock config in ~/.config/linux_post_install/ | PASS — scan_tier2 finds all 3 config files |
| (c) | scan finds mock data in ~/.local/share/linux_post_install/ | PASS — scan_tier3 finds ai/, logs/, last_cmd_output |
| (d) | --yes removes tier 1 without prompting | PASS — YES_MODE=1 skips confirm() |
| (e) | --yes --config --data removes all three tiers | PASS — DEL_CONFIG=1 DEL_DATA=1 triggers all removals |
| (f) | idempotent: second run finds nothing | PASS — scan returns empty when dirs/files absent |
| (g) | bashrc entries cleanly removed | PASS — 3 pos lines removed, non-pos lines preserved |
| (h) | systemd services disabled | PASS — systemctl disable --now called for each found service |
| (i) | git repo NOT removed | PASS — no git-related paths in any scan/remove function |
| (j) | confirm default=y | PASS — confirm() in common.sh defaults to y |

## Diff stats

```
 bin/pos                                          |  2 +-
 bin/pos-system-uninstall                         | 18 +++++++++++-----
 DOC/AGENT_Context_Project.md                     | 33 ++++++++++++-----------
 DOC/POS.md                                       |  1 +
 DOC/howto/system.md                              | 35 +++++++++++++++++++++++++++++++++--
 completions/pos.bash                             |  1 +
 6 files changed, 66 insertions(+), 24 deletions(-)
```

## Gates

| Gate | Result |
|------|--------|
| `bash -n bin/pos-system-uninstall` | OK |
| `bash -n bin/pos` | OK |
| `make gen` | OK (idempotent) |
| `make check` | OK |
| `make lint` | 0 FAIL, 0 WARN |

REPORT_PATH: ./AgentsReport/builder/2026-08-25_uninstall.md
