# Lesson: `set -e` + `wait "$pid"; rc=$?` kills the shell on non-zero child exit

**Symptom:** a daemon loop crash-looping with status = a background child's exit code
(set -euo pipefail shell).

**Debugging approach that worked:**
1. Before theorizing, reproduce the failing command chain in isolation AND check the exact
   exit code of each link (ffmpeg on absent device returned 254 — not the "expected" 231
   from /dev/null!).
2. Bisect the propagation path: raw command → chain wrapper → bg child spawn → CHLD trap
   reaping → reap_commands wait fallback. Using `bash -x` on a byte-identical reduced
   script (trap_full.sh) pinpointed the death at `+ wait <pid>`.
3. Baseline shell semantics test: `bash -c 'set -e; false; echo REACHED'` → exits without
   REACHED. Proves `;` does NOT shield a failing simple command from errexit. Many devs
   wrongly assume `cmd; rc=$?` is always safe — it is NOT under `set -e`.
4. Bash `wait -n` in a while-condition ALSO conceals non-zero child exits (loop body
   skipped) → a "reaping" trap silently loses the failure info → downstream fallbacks
   go to the dangerous path.

**Key insight:** with `set -euo pipefail`, ANY background failure can become a main-shell
death if reaped via `wait "$pid"` in a plain command list. The safe capture is
`rc=0; wait "$pid" 2>/dev/null || rc=$?` (errexit suppressed by `||`), or run reaping
inside `if wait ...; then ... else rc=$?; fi`.
