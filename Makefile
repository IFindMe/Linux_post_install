.PHONY: check gen hook

## check   — verify repo self-consistency (syntax, exec bits, doc/code sync, smoke)
check:
	./scripts/check-sync.sh

## gen     — regenerate code-derived doc sections + completion flags
gen:
	./scripts/gen-docs.sh

## hook    — install the opt-in pre-commit hook (runs `make check`)
hook:
	./scripts/install-hooks.sh
