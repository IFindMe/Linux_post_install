.PHONY: check gen hook lint test

## check   — verify repo self-consistency (syntax, exec bits, doc/code sync, smoke)
check:
	./scripts/check-sync.sh

## gen     — regenerate code-derived doc sections + completion flags
gen:
	./scripts/gen-docs.sh

## lint    — convention gate (shebang/pipefail, headers, deps-guard ordering, stdin, secrets, docs)
lint:
	./scripts/lint-conventions.sh

## test    — regression suite (zero-dependency runner; no network, no system changes)
test:
	./tests/run-tests.sh

## hook    — install the opt-in pre-commit hook (runs `make check`)
hook:
	./scripts/install-hooks.sh
