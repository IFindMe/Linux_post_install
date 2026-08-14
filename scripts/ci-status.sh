#!/usr/bin/env bash
# Report whether the `gates` workflow has finished for a commit, using only
# git against the remote (no SSH to the runner box, no API tokens).
#
# `.gitea/workflows/lint.yml` pushes a lightweight tag `ci-ok/<sha>` when the
# gates pass and `ci-fail/<sha>` when they fail. This script reads those tags
# with `git ls-remote`.
#
# Usage:
#   scripts/ci-status.sh [<sha>]          # one-shot check (default: current HEAD)
#   scripts/ci-status.sh --wait [<sha>]   # poll until done (max 10 min)
#
# Exit codes: 0 = green, 1 = red, 2 = still running / not reported.
set -euo pipefail

REMOTE="${CI_STATUS_REMOTE:-origin}"
INTERVAL=10
TIMEOUT=600

sha="${1:-}"
if [ "$sha" = "--wait" ]; then
    wait=1
    sha="${2:-}"
fi
[ -n "$sha" ] || sha="$(git rev-parse HEAD)"

check() {
    local ok="" fail=""
    ok="$(git ls-remote "$REMOTE" "refs/tags/ci-ok/$sha" | awk '{print $1}')"
    fail="$(git ls-remote "$REMOTE" "refs/tags/ci-fail/$sha" | awk '{print $1}')"
    if [ -n "$ok" ]; then
        echo "GREEN — gates passed for $sha ($ok)"
        return 0
    fi
    if [ -n "$fail" ]; then
        echo "RED — gates failed for $sha ($fail)"
        return 1
    fi
    echo "PENDING — no gate result yet for $sha"
    return 2
}

if [ "${wait:-0}" -ne 1 ]; then
    if check; then
        exit 0
    else
        rc=$?
        exit "$rc"
    fi
fi

deadline=$((SECONDS + TIMEOUT))
while :; do
    out="$(check 2>&1)" && { echo "$out"; exit 0; }
    rc=$?
    if [ "$rc" -eq 1 ]; then
        echo "$out"
        exit 1
    fi
    if (( SECONDS >= deadline )); then
        echo "TIMEOUT after ${TIMEOUT}s — no gate result for $sha"
        exit 2
    fi
    sleep "$INTERVAL"
done
