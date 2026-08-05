#!/usr/bin/env bash
set -euo pipefail
# Opt-in git pre-commit hook that runs `make check` before every commit.
# Run `make hook` (or ./scripts/install-hooks.sh) once per clone.
#
# Skips itself when the commit is purely merge/conflict-resolution driven.

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/.git/hooks/pre-commit"

cat > "$hook" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
cd "$root"
exec make check
EOF
chmod +x "$hook"
echo "pre-commit hook installed: $hook"
