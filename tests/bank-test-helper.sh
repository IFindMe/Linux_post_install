#!/usr/bin/env bash
# tests/bank-test-helper.sh — minimal shim that sources bank-lib.sh for unit
# testing.  Provides a stub `err()` so bank-lib.sh can load without the full
# common.sh / menu-lib.sh dependency chain.
set -euo pipefail

# Stub err() — bank-lib.sh is contractually "never exits" but bank_valid_name
# callers sometimes chain via `|| err …`.  This version returns 1 so the test
# harness can assert rc.
err() { printf 'ERROR: %s\n' "$*" >&2; return 1; }

# Source the library under test.
source "$ROOT/lib/bank-lib.sh"
