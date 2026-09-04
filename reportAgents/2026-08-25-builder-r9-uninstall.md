# Builder Report — pos-system-uninstall

## TL;DR
- **Status:** IN PROGRESS
- **Files changed:** bin/pos-system-uninstall (new), DOC/POS.md, DOC/howto/system.md, GEN regen
- **Gates:** pending
- **Probe:** pending

---

## Step 1: Create bin/pos-system-uninstall
[DONE]

Created `bin/pos-system-uninstall` — a 3-tier interactive uninstaller.
- bash -n: PASS
- Flags: --yes, --config, --data
- Three scan/display/remove functions per tier
- Shell integration removal via sed (matches postinstall.sh patterns)
- Service cleanup with daemon-reload

## Step 2: Update DOC/POS.md
[PENDING]

## Step 3: Update DOC/howto/system.md
[PENDING]

## Step 4: Run make gen && gates
[PENDING]

## Step 5: Verification probe (mock HOME)
[PENDING]
