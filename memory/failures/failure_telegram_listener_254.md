# Failure: telegram-listener exit-254 crash loop (LattePanda, 2026-09-12)

**Root cause:** No webcam device on host (`/dev/video*` absent). The `/capture` command chain
(`ffmpeg -f v4l2 -i /dev/video0 ...` from telegram_commands.env) fails fast with exit 254.
The listener (bin/pos-communication-telegram-listener) spawns that chain as a bg child; its
SIGCHLD trap `while _p=$(wait -n 2>/dev/null); do _EXIT_CODES[$_p]=$?; done` only stores exits
when `wait -n` returns 0 (non-zero exit → while-condition false → body skipped → pid consumed
but never recorded). `reap_commands()` then falls into `wait "$pid" 2>/dev/null; rc=$?`;
a failing `wait` under `set -euo pipefail` kills the whole shell **before** `rc=$?` runs
(`set -e` does NOT exempt a failing simple command followed by `;`). Verified: raw ffmpeg→254,
exact chain→254, trap_full.sh (byte-identical trap/reap + real ffmpeg child)→EXIT=254.

**Loop persistence:** Restart=always + RestartSec=5 + every instance starts `local offset=0`
and dies before confirming the previous getUpdates → same pending updates re-fetch and
re-execute on every restart → /capture fails 254 again → infinite crash loop (NRestarts 80+
in ~1h). Journal bursts byte-identical across instances (160 execs/16 starts ~10 min).

**Prevention:**
1. reap fallback must tolerate non-zero child exits: `rc=0; wait "$pid" 2>/dev/null || rc=$?`
   (or capture inside if/||). Never `wait "$pid"; rc=$?` under set -e.
2. CHLD trap should record non-zero exits: `while _p=$(wait -n 2>/dev/null); do ...; done`
   cannot observe a failing exit — use `wait -n; _p=$?`-safe pattern or `|| true` + $? capture.
3. Command map entries should pre-check devices (`[ -e /dev/video0 ] || error`) so a
   permanently-broken command cannot crash the daemon.
4. Persist the getUpdates offset (or confirm after processing) so replays stop on restart.
5. Diagnose "slow bot" by checking `systemctl --user show ... -p NRestarts` / journal
   `status=254` FIRST — crash-loop downtime beats processing speed by orders of magnitude.
