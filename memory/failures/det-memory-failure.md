# Failure: hermetic Bash suite fails on live host via config/lock leaks (2026-09-19)
Symptom: 5 test files failed (22 checks) while tools were correct.
Cause A: ai-server tests did not isolate CONFIG_FILE, so live ~/.config/linux_post_install/ai.env (LLAMACPP_PORT=30000, LLAMACPP_HOST=100.100.3.6) overrode expected defaults via by-design flags>env>file precedence (bin/pos-ai-server:18,33-58); leaked endpoint also stalled unstubbed curl probes ~20s each (suite 327s vs <90s budget).
Cause B: telegram tests did not sandbox XDG_RUNTIME_DIR, so the production-correct flock singleton (bin/pos-communication-telegram-listener:834-838) collided with the live daemon's /run/user/1000 lock; daemon under test exited rc=1 before executing anything.
Proof: all 5 files PASS standalone with one env var changed (CONFIG_FILE=empty sandbox file; XDG_RUNTIME_DIR=sandbox dir).
Prevention: every test that exercises config-loading tools must pin CONFIG_FILE/CONFIG_DIR to the sandbox and -u/override ambient *_PORT/*_HOST vars; every test that starts a singleton daemon must sandbox XDG_RUNTIME_DIR; stub curl everywhere or wrap status probes in timeout so leaks fail fast.
Report: AgentsReport/detective/2026-09-19_failing-suite.md
