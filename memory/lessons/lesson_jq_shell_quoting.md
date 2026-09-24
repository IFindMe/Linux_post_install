# Lesson: `\"` inside single-quoted jq filters in `$(...)` is literal (2026-09-23)

## Context
`pos ai hf info` failed with `jq: ... join(\", \")`. Eight filters in
`cmd_info` (`bin/pos-ai-hf`) were written as
`var="$(... | jq -r '...join(\", \")...')"` — backslash-escaped inner quotes.

## Trap
`$(...)` starts a **fresh quoting context**: the outer assignment's double
quotes do NOT govern text inside it. Inside `$(...)` the filter sits in
syntactic **single quotes**, where backslash is literal — so `\"` reaches jq
verbatim as backslash-quote → `INVALID_CHARACTER` compile error (rc=3), and
under `set -euo pipefail` the command aborts before any output.

## Rule
- jq filter in single quotes inside `$(...)`: use plain `"` — NEVER `\"`.
  Correct: `jq -r '.tags // [] | join(", ")'`.
- `\"` is correct ONLY when directly inside double quotes, e.g.
  `awk "BEGIN { printf \"...\" }"`. Same file had both; grep for `\\"` cannot
  distinguish — check the enclosing quote context per hit.
- `bash -n` cannot catch this (valid shell, invalid runtime filter string).
  Prove filters with a stub-JSON red/green check, including `{}`/empty-array
  edge cases for `//` fallbacks.

## Evidence
Detective report + mutation proof + Reviewer approval (2026-09-23 hf-info
chain); 8-line fix, siblings (`search`/`files`/`download`/…) verified clean.
