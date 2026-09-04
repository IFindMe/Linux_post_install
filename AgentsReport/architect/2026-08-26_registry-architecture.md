# Architect Report — Self-Describing Command Registry for POS

**Date:** 2026-08-26
**Status:** DECISION_READY

---

## TL;DR

- **Decision:** Add a thin `lib/registry.sh` library that parses `# POS_*:` headers into a queryable API; two new optional headers (`# POS_DEPS:`, `# POS_EXAMPLES:`) extend existing conventions; no framework, no new abstraction layer.
- **Key insight:** The existing header system is already 80% of a registry. The missing piece is a shared parsing library so every consumer stops reimplementing `sed` + `grep` header reading.
- **Scope:** `lib/registry.sh` (new), `scripts/gen-docs.sh` (extend), `bin/pos-tree` (use registry), `templates/pos-tool.sh` (document new headers), docs. All existing tools keep working unchanged.
- **Migration:** Zero-downtime — new headers are optional. Tools add `# POS_DEPS:` and `# POS_EXAMPLES:` incrementally. Registry degrades gracefully when headers are absent.
- **Open items:** `pos help` and `pos menu` are future consumers (not in this phase). Dashboard is out of scope.

---

## Decision 1: Header Format — Extend, Don't Replace

### Problem

The spec asks for dependencies, curated examples, and a shared query API. Currently, each consumer (`pos tree`, `pos <category> --help`, `gen-docs.sh`, `pos config`) independently implements `sed`/`grep` header parsing with its own logic.

### Decision

Add two new optional `# POS_*:` header lines. Keep all existing headers unchanged.

### Exact Syntax

```bash
# POS_DEPS: <binary1> [binary2 ...]
# POS_EXAMPLES: <command> | <description>
```

**Rules:**
- All new headers are **optional** — tools that don't declare them simply won't expose that metadata. Progressive metadata preserved.
- `# POS_DEPS:` is space-separated binary names (what `command -v` checks, not apt package names).
- `# POS_EXAMPLES:` can appear on multiple lines — each is `<command> | <description>` (pipe-delimited, max one `|`).
- Headers must appear between the shebang/strict-mode block (lines 1–6) and the first non-comment line.
- Gen-docs and lint only parse headers from the first ~10 lines of each file.

**Existing headers (unchanged):**

```bash
# POS: <category> <command> — <description>
# POS_FLAGS: --flag1 --flag2
# POS_SUBCMDS: sub1 sub2 sub3
# POS_CONFIG: <scope> | <env-file> | <KEY>=<flags>:<desc> | ...
```

**New headers (optional):**

```bash
# POS_DEPS: docker nmap jq
# POS_EXAMPLES: pos network scan 192.168.1.0/24 | Scan a /24 CIDR
# POS_EXAMPLES: pos network scan 10.0.0.0/28 --full | Full scan with OS detection
```

### Example: Minimal Tool (No Change Needed)

```bash
#!/usr/bin/env bash
set -euo pipefail
# POS: ssh load-keys — Load all SSH keys into the agent
# ... rest of script
```

### Example: Rich Tool

```bash
#!/usr/bin/env bash
set -euo pipefail
# POS: network download — aria2 RPC daemon + queue control (add/torrent/metalink, watch, limits)
# POS_SUBCMDS: start stop status add torrent metalink list info files peers pause resume remove purge move limit set watch restart retry replace menu
# POS_FLAGS: --dir --out --split --seed --force --upload --gid --tmux
# POS_DEPS: aria2c jq curl
# POS_EXAMPLES: pos network download add https://example.com/file.zip | Download a file
# POS_EXAMPLES: pos network download status | Show download queue status
# POS_EXAMPLES: pos network download --tmux start aria2 daemon with live view
```

### Rationale

| Option | Architecture | Advantages | Costs | Risks | When to choose |
|--------|-------------|------------|-------|-------|----------------|
| **A: Extend existing headers** | Add `# POS_DEPS:` and `# POS_EXAMPLES:` alongside existing headers | Backward compatible, zero migration cost, progressive metadata, consistent with existing patterns | Two new header formats to parse | Low — optional headers degrade gracefully | **Chosen** — smallest sufficient design |
| B: Unified YAML frontmatter | Replace all `# POS_*:` with a YAML block in each file | Richer structure, easier to extend | Breaks all existing consumers, requires migration of 40+ tools, adds YAML dependency | High — YAML parser availability in bash, migration burden | Only if the header system were fundamentally inadequate |
| C: Separate registry file | `registry/<tool>.yaml` per tool | Clean separation, richer metadata | Duplicates what headers already provide, extra files to maintain, sync risk between header and registry | Medium — source of truth drift | Only if headers couldn't hold the metadata |

**Option A wins** because the existing header system already works, is already the source of truth for gen-docs output, and the new metadata (deps, examples) fits naturally into the comment-header format.

### Constraints for Builder

- `# POS_DEPS:` line: `sed -n '/^# POS_DEPS: /{s/^# POS_DEPS: //;p;q}' <file>` — space-separated tokens.
- `# POS_EXAMPLES:` lines: `grep '^# POS_EXAMPLES:' <file | sed 's/^# POS_EXAMPLES:[[:space:]]*//'` — one per line, `|`-delimited command|description.
- The `# POS:` header line **must remain the first metadata line** after shebang/strict-mode. New headers go after existing headers, before any code.

[DECIDED]

---

## Decision 2: Registry Library — `lib/registry.sh`

### Problem

Four consumers independently parse tool headers with their own `sed`/`grep` patterns:
- `bin/pos` `_pos_category_help()` (lines 68–123): reads `# POS:` and `# POS_SUBCMDS:` per tool
- `bin/pos-tree` (lines 47–68): reads `# POS:` and `# POS_SUBCMDS:` per tool
- `scripts/gen-docs.sh` (lines 30–46): reads `# POS:`, `# POS_FLAGS:`, `# POS_SUBCMDS:`, `# POS_CONFIG:` per tool
- `lib/config-ui.sh` (lines 50–57): reads `# POS_CONFIG:` per tool

Each reimplements the same header-reading pattern. Adding new headers means updating every consumer.

### Decision

Create `lib/registry.sh` — a thin library (target ~180 lines) that provides a shared API for querying tool metadata from `# POS_*:` headers.

### Data Structures

All data lives in bash associative arrays and indexed arrays, populated by a single `reg_scan` call.

```bash
# Indexed array — all tool keys, sorted (LC_ALL=C)
declare -a _reg_tools=()

# Associative arrays — keyed by tool key (e.g., "network-download", "config")
declare -A _reg_cat=()        # tool → category ("" for category-less)
declare -A _reg_desc=()       # tool → description (text after "— ")
declare -A _reg_flags=()      # tool → raw POS_FLAGS value
declare -A _reg_subcmds=()    # tool → raw POS_SUBCMDS value
declare -A _reg_deps=()       # tool → raw POS_DEPS value
declare -A _reg_examples=()   # tool → newline-joined POS_EXAMPLES lines

# Config is special: multiple headers per tool, multiple fields per header.
# Stored as pipe-delimited lines keyed by scope (not tool).
declare -a _reg_config_scopes=()  # unique scope names, sorted
declare -A _reg_config_keys=()    # scope → newline-joined key|flags|desc lines
```

**Why not store everything in one mega-array?** Bash associative arrays can't hold structured records. Separate arrays per field keep lookups O(1) and code readable.

### Tool Key Convention

Tool keys match the existing filename convention:
- `bin/pos-network-download` → key `network-download`, category `network`
- `bin/pos-config` → key `config`, category `""` (category-less)
- `bin/pos-ai-alias` → key `ai-alias`, category `ai`

### API

```bash
# ── Initialization ──────────────────────────────────────────────

reg_scan [dir]
    Scan all pos-* files in dir (default: auto-detect from BASH_SOURCE).
    Populates _reg_tools, _reg_cat, _reg_desc, _reg_flags, _reg_subcmds,
    _reg_deps, _reg_examples, _reg_config_scopes, _reg_config_keys.
    Must be called before any other reg_* function.
    Uses LC_ALL=C for deterministic sort.

# ── Discovery ───────────────────────────────────────────────────

reg_list
    Echo sorted list of all tool keys, one per line.

reg_categories
    Echo sorted unique category names (empty string for category-less tools).

reg_tools_in <category>
    Echo sorted tool keys belonging to <category>.
    Pass "" for category-less tools.

# ── Lookup ──────────────────────────────────────────────────────

reg_lookup <tool> <field>
    Echo a field's value for a tool. Fields:
      cat, desc, flags, subcmds, deps, examples
    Returns empty string if field not set or tool not found.
    Exit code: 0 if tool found, 1 if not.

reg_config_scopes
    Echo sorted list of unique config scope names.

reg_config_keys <scope>
    Echo key|flags|description lines for a scope (newline-delimited).

reg_config_envfile <scope>
    Echo the env-file basename for a scope.
    Exit code: 0 if found, 1 if not.

# ── Iteration ───────────────────────────────────────────────────

reg_each <callback>
    Call <callback> for each tool, passing:
      <callback> <category> <tool_key> <description>
    Category is empty for category-less tools.

# ── Convenience (for common patterns) ──────────────────────────

reg_tool_exists <tool>
    Exit 0 if tool is registered, 1 otherwise.

reg_tools_for_category <category>
    Alias for reg_tools_in. Kept for clarity.
```

### Source Pattern

```bash
# lib/registry.sh — no shebang (library, not executable)
# Sourced opt-in by consumers that need tool metadata.

# Common.sh helpers (guarded fallback — mirrors lib/config-ui.sh pattern)
declare -F log  >/dev/null || log()  { echo "[+] $*"; }
declare -F warn >/dev/null || warn() { echo "[!] $*"; }
declare -F err  >/dev/null || err()  { echo "ERROR: $*" >&2; exit 1; }

# ── Tool directory detection ────────────────────────────────────
# Repo:   lib/registry.sh → ../bin
# Install: /usr/local/bin/registry.sh → /usr/local/bin (same dir)
_reg_tools_dir() {
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" 2>/dev/null && pwd)"
    if [ -d "$dir" ] && ls "$dir"/pos-* &>/dev/null; then
        echo "$dir"
    else
        dirname "${BASH_SOURCE[0]}"
    fi
}

# ── Data stores ─────────────────────────────────────────────────
declare -a _reg_tools=()
declare -A _reg_cat=()
declare -A _reg_desc=()
declare -A _reg_flags=()
declare -A _reg_subcmds=()
declare -A _reg_deps=()
declare -A _reg_examples=()
declare -a _reg_config_scopes=()
declare -A _reg_config_keys=()

# ── reg_scan ────────────────────────────────────────────────────
reg_scan() {
    local dir="${1:-$(_reg_tools_dir)}" f
    local old LC_ALL_PREV="$LC_ALL"
    export LC_ALL=C

    _reg_tools=()
    # Clear all associative arrays
    for key in "${!_reg_cat[@]:-}"; do
        unset "_reg_cat[$key]" "_reg_desc[$key]" "_reg_flags[$key]"
        unset "_reg_subcmds[$key]" "_reg_deps[$key]" "_reg_examples[$key]"
    done
    _reg_config_scopes=()
    for scope in "${!_reg_config_keys[@]:-}"; do
        unset "_reg_config_keys[$scope]"
    done

    local -A scope_seen=()

    for f in "$dir"/pos-*; do
        [ -x "$f" ] || continue
        local name="${f##*/pos-}"
        local key cat sub
        if [[ "$name" == *-* ]]; then
            cat="${name%%-*}"
            sub="${name#*-}"
        else
            cat=""
            sub="$name"
        fi
        key="$sub"

        _reg_tools+=("$key")
        _reg_cat["$key"]="$cat"

        # POS: — description (text after first "— ")
        local pos_line
        pos_line="$(sed -n '/^# POS: /{s/^# POS: //;p;q}' "$f" 2>/dev/null)"
        _reg_desc["$key"]="${pos_line#*— }"

        # POS_FLAGS:
        _reg_flags["$key"]="$(sed -n '/^# POS_FLAGS: /{s/^# POS_FLAGS: //;p;q}' "$f" 2>/dev/null)"

        # POS_SUBCMDS:
        _reg_subcmds["$key"]="$(sed -n '/^# POS_SUBCMDS: /{s/^# POS_SUBCMDS: //;p;q}' "$f" 2>/dev/null)"

        # POS_DEPS:
        _reg_deps["$key"]="$(sed -n '/^# POS_DEPS: /{s/^# POS_DEPS: //;p;q}' "$f" 2>/dev/null)"

        # POS_EXAMPLES: (may appear multiple times — join with newlines)
        local examples=""
        examples="$(sed -n '/^# POS_EXAMPLES: /{s/^# POS_EXAMPLES: //;p}' "$f" 2>/dev/null)"
        _reg_examples["$key"]="$examples"

        # POS_CONFIG: (may appear multiple lines per file)
        local line
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            line="${line#*POS_CONFIG:}"
            local scope="${line%%|*}"
            scope="${scope// }"
            [ -n "$scope" ] || continue
            _reg_config_keys["$scope"]+="${_reg_config_keys[$scope]:+$'\n'}$line"
            if [ -z "${scope_seen[$scope]:-}" ]; then
                scope_seen["$scope"]=1
                _reg_config_scopes+=("$scope")
            fi
        done < <(grep '^# POS_CONFIG:' "$f" 2>/dev/null || true)
    done

    # Sort tools
    mapfile -t _reg_tools < <(printf '%s\n' "${_reg_tools[@]}" | sort)
    # Sort config scopes
    mapfile -t _reg_config_scopes < <(printf '%s\n' "${_reg_config_scopes[@]}" | sort -u)

    export LC_ALL="$LC_ALL_PREV"
}

# ── Discovery ───────────────────────────────────────────────────
reg_list() { printf '%s\n' "${_reg_tools[@]}"; }

reg_categories() {
    local -A cats=()
    local t
    for t in "${_reg_tools[@]}"; do
        cats["${_reg_cat[$t]}"]=1
    done
    printf '%s\n' "${!cats[@]}" | sort
}

reg_tools_in() {
    local cat="$1" t
    for t in "${_reg_tools[@]}"; do
        [ "${_reg_cat[$t]}" = "$cat" ] && echo "$t"
    done
}

# ── Lookup ──────────────────────────────────────────────────────
reg_lookup() {
    local tool="$1" field="$2"
    case "$field" in
        cat)     echo "${_reg_cat[$tool]:-}" ;;
        desc)    echo "${_reg_desc[$tool]:-}" ;;
        flags)   echo "${_reg_flags[$tool]:-}" ;;
        subcmds) echo "${_reg_subcmds[$tool]:-}" ;;
        deps)    echo "${_reg_deps[$tool]:-}" ;;
        examples) echo "${_reg_examples[$tool]:-}" ;;
        *)       return 1 ;;
    esac
}

reg_config_scopes() { printf '%s\n' "${_reg_config_scopes[@]}"; }

reg_config_keys() {
    local scope="$1"
    echo "${_reg_config_keys[$scope]:-}"
}

reg_config_envfile() {
    local scope="$1" line
    line="$(echo "${_reg_config_keys[$scope]:-}" | head -1)"
    [ -n "$line" ] || return 1
    line="${line#*|}"   # drop scope
    local env="${line%%|*}"
    echo "${env// }"
}

# ── Iteration ───────────────────────────────────────────────────
reg_each() {
    local cb="$1" t
    for t in "${_reg_tools[@]}"; do
        "$cb" "${_reg_cat[$t]}" "$t" "${_reg_desc[$t]}"
    done
}

# ── Convenience ─────────────────────────────────────────────────
reg_tool_exists() {
    [ -n "${_reg_desc[$1]+x}" ]
}
```

### Rationale

| Option | Architecture | Advantages | Costs | Risks | When to choose |
|--------|-------------|------------|-------|-------|----------------|
| **A: Regenerate-on-source library** | `reg_scan` parses all files into bash arrays on first call | O(1) lookups after scan, no external deps, works from /usr/local/bin, bash-native | ~180 lines of code, scan cost at startup (~5ms for 40 tools) | Low — scan is fast enough for interactive use | **Chosen** — matches project's bash-only, no-framework philosophy |
| B: Cached JSON file | `make gen` produces `registry.json`, consumers parse with `jq` | Fast lookups, rich queries | Requires `jq` at runtime (currently a dep, but adds coupling), extra build step, staleness risk | Medium — JSON dependency for all consumers | Only if performance of header parsing became a bottleneck (it won't for 40 tools) |
| C: Per-tool .meta files | Each tool has a sidecar `pos-<tool>.meta` | Clean separation, rich format | Duplicates header data, extra files to maintain, sync drift risk | Medium — two sources of truth | Only if headers were fundamentally limited |

**Option A wins** because:
1. Headers are already the source of truth — no sync risk.
2. The scan takes ~5ms for 40 tools — no performance concern.
3. Works from `/usr/local/bin/` (all libs live there after install).
4. Matches the project's "no unnecessary framework" philosophy.
5. Follows the pattern established by `lib/config-ui.sh`.

### Source Chain

```bash
# In any consumer:
source "$(dirname "$0")/../lib/registry.sh" 2>/dev/null || source "$(dirname "$0")/registry.sh"
reg_scan
# ... use reg_list, reg_lookup, etc.
```

[DECIDED]

---

## Decision 3: Consumer Integration

### Problem

Four consumers need to use the registry. Each has different requirements:
- `bin/pos-tree` needs tree-building from tool data
- `bin/pos` `_pos_category_help()` needs category → tool listing
- `scripts/gen-docs.sh` needs all metadata for code generation
- `lib/config-ui.sh` needs config scopes and keys

### Decision

Migrate consumers to `lib/registry.sh` in this order (highest value first):

#### 3.1: `bin/pos-tree` (Priority: HIGH)

**Current state** (lines 47–68): Scans `pos-*` files independently, reads `# POS:` and `# POS_SUBCMDS:` via `sed`.

**After migration:**
```bash
source "$(dirname "$0")/../lib/registry.sh" 2>/dev/null || source "$(dirname "$0")/registry.sh"
reg_scan

# Build tree from registry instead of scanning files
for tool in $(reg_list); do
    cat="$(reg_lookup "$tool" cat)"
    desc="$(reg_lookup "$tool" desc)"
    deps="$(reg_lookup "$tool" deps)"
    # ... add to tree, annotate with deps if present
done
```

**Enhancement:** When `# POS_DEPS:` is present, show it in the tree view:
```
├── docker ps                    # Enhanced container overview (health, IPs, ports, uptime)
│   [deps: docker]
```

This is the highest-value consumer change — it proves the registry works at runtime and shows the immediate benefit of new metadata.

**Implementation note:** Keep the existing `add()` / `render()` tree-building logic. Replace only the data-collection loop (lines 47–68) with registry calls. The tree structure is already correct from filenames + `POS_SUBCMDS`.

#### 3.2: `scripts/gen-docs.sh` (Priority: HIGH)

**Current state** (lines 30–46): Collects tools into a pipe-delimited array via direct `sed` calls.

**After migration:**
```bash
# In the tools collection loop, use registry for new fields
# Keep the existing collection pattern for backward compatibility
# (gen-docs.sh has its own sorting and rendering logic)

# Add deps and examples to the tools array format
tools+=("$cat|$sub|$desc|$flags|$subcmds|$deps|$examples")
```

**New gen blocks:**
- Add `deps` and `examples` columns to `gen_tree()`, `gen_dispatch()`, `gen_filetable()`.
- These become visible in `DOC/AGENT_Context_Project.md` once tools add the new headers.

**Important:** The existing `gen_*` functions use their own `tools` array (not the registry) because they need specific formatting. The registry provides the raw data; gen-docs formats it. This avoids tight coupling between the generator and the library.

**Alternative considered:** Have gen-docs source the registry directly. Rejected because gen-docs needs the data in a specific format (pipe-delimited array) and the registry's data structure is an implementation detail. Keeping the data flow explicit (`registry → gen-docs tools array → gen_* functions`) is cleaner.

#### 3.3: `bin/pos` `_pos_category_help()` (Priority: MEDIUM)

**Current state** (lines 68–123): Scans `pos-<cat>-*` files, reads `# POS:` and `# POS_SUBCMDS:` per file.

**After migration:**
```bash
_pos_category_help() {
    local cat="$1"
    source "$(dirname "$0")/../lib/registry.sh" 2>/dev/null || source "$(dirname "$0")/registry.sh"
    reg_scan
    
    echo "pos $cat — $cat tools"
    echo
    echo "USAGE"
    echo "  pos $cat <command> [args]"
    echo
    echo "COMMANDS"
    for tool in $(reg_tools_in "$cat"); do
        local desc deps
        desc="$(reg_lookup "$tool" desc)"
        deps="$(reg_lookup "$tool" deps)"
        printf '  %-28s%s' "$tool" "$desc"
        [ -n "$deps" ] && printf '  [deps: %s]' "$deps"
        echo
        # ... subcommands from reg_lookup "$tool" subcmds
    done
    echo
    echo "Run 'pos $cat <command> --help' for details on a command."
    exit 0
}
```

**Trade-off:** This adds a `reg_scan` call every time `pos <category>` runs. For 40 tools, the scan takes ~5ms — negligible for interactive use. If profiling shows this matters, `pos` could cache the scan in a temp file (but this is premature optimization).

**Alternative considered:** Keep `_pos_category_help()` using direct `sed` (no registry dependency). Rejected because the whole point is to centralize header parsing. The 5ms scan cost is acceptable.

#### 3.4: `lib/config-ui.sh` (Priority: LOW — separate decision)

**Current state** (lines 50–203): Has its own header parsing for `# POS_CONFIG:` and `# POS_KEYS:`. The config library is already a mature, working abstraction.

**Decision: Do NOT integrate config-ui.sh with the registry in this phase.**

**Rationale:**
1. config-ui.sh already works correctly and is well-tested.
2. Its parsing is specialized (multi-line key fields, `*plugins` expansion, `*providers` expansion).
3. Integrating it with the registry would require the registry to handle all config-ui's edge cases, bloating the library.
4. config-ui.sh's `cfg_headers()` / `cfg_scopes()` / `cfg_scope_keys()` API is already the "registry" for config consumers.

**Future:** When config-ui.sh needs maintenance, it could source the registry for its initial scan. But this is not needed now.

### Rationale

| Option | Architecture | Advantages | Costs | Risks | When to choose |
|--------|-------------|------------|-------|-------|----------------|
| **A: Incremental migration** | Migrate tree + gen-docs first, then pos, defer config-ui | Lowest risk, proves value early, no breaking changes | Some consumers still use direct sed during transition | Low — transition period is harmless | **Chosen** — smallest risky step |
| B: Big-bang migration | Rewrite all consumers at once | Consistent from day one | High risk, many things can break, hard to review | High — one bad refactor breaks everything | Only if the codebase were much smaller |
| C: No migration — just add the library | Create registry.sh but don't change any consumers | Library exists for future use | No immediate value, consumers still duplicate logic | Low — but pointless | Only if the task were just "create a library" |

[DECIDED]

---

## Decision 4: Migration Strategy — Zero-Downtime Incremental

### Problem

40+ tools exist. All must keep working. The new headers are optional. No tool should require changes to function.

### Decision

**Phase 1 (this implementation):**
1. Create `lib/registry.sh` with full API.
2. Update `scripts/gen-docs.sh` to parse new headers (degrades gracefully when absent).
3. Migrate `bin/pos-tree` to use registry (proves runtime value).
4. Update `templates/pos-tool.sh` to document new headers.
5. Update `DOC/DEV.md` and `DOC/AGENT_Context_Project.md` with new header format.

**Phase 2 (future, out of scope):**
1. Migrate `bin/pos` `_pos_category_help()` to use registry.
2. Enhance `pos help` to show registry metadata (deps, examples).
3. Add `# POS_DEPS:` and `# POS_EXAMPLES:` to tools incrementally (start with 3–5 representative tools per category).

**Phase 3 (future, out of scope):**
1. `pos menu` — interactive menu from registry (new tool).
2. `pos dashboard` — status dashboard from registry (new tool).

### Incremental Adoption for Tool Authors

1. Add `# POS_DEPS: docker jq` to your tool's header block. Done — deps appear in registry.
2. Add `# POS_EXAMPLES: pos <tool> <args> | Description` lines. Done — examples appear in registry.
3. No other changes required. The tool keeps working exactly as before.
4. When you run `make gen`, the new metadata appears in generated docs.

### Tool Template Update

`templates/pos-tool.sh` gets new header documentation:

```bash
# ────────────────────────────────────────────────────────────────
# TEMPLATE — new `pos` CLI tool
#
#  1. Copy:     cp templates/pos-tool.sh bin/pos-<category>-<command>
#  2. Header:   add a `# POS:` line right after the shebang/strict-mode
#               lines (single source of truth for generated docs):
#                 # POS: <category> <command> — one-line description
#                 # POS_FLAGS: --flag1 --flag2   (flag-style tools only)
#                 # POS_SUBCMDS: sub1 sub2       (multi-command tools only)
#                 # POS_DEPS: binary1 binary2    (runtime deps, optional)
#                 # POS_EXAMPLES: pos <tool> <args> | Description  (optional)
#  3. ...
```

### Lint Gate Update

`scripts/lint-conventions.sh` gets a new WARN check:
- If `# POS_DEPS:` is present, validate that each token looks like a binary name (no spaces, no special chars). This is a soft check — WARN on malformed deps, not FAIL.

[DECIDED]

---

## Decision 5: Scope Boundaries

### Approved Scope

```text
In scope:
  lib/registry.sh                        — NEW FILE, ~180 lines
  scripts/gen-docs.sh                    — Extend tools array, add deps/examples to gen_* functions
  bin/pos-tree                           — Migrate to use registry (replace file-scanning loop)
  templates/pos-tool.sh                  — Document new headers in template comments
  DOC/DEV.md                             — Document new header format and registry usage
  DOC/AGENT_Context_Project.md           — Update line count table for lib/registry.sh, gen blocks updated by make gen
  scripts/lint-conventions.sh            — Optional: WARN for malformed POS_DEPS

Not in scope:
  bin/pos _pos_category_help()           — Phase 2 (future)
  pos help enhancements                  — Phase 2 (future)
  pos menu (new tool)                    — Phase 3 (future)
  pos dashboard (new tool)               — Phase 3 (future)
  Adding POS_DEPS/POS_EXAMPLES to existing tools — Individual tool authors, incremental
  lib/config-ui.sh integration          — Deferred (already works, specialized parsing)
  completions/pos.bash changes          — No new completion data needed (deps/examples aren't completable)
  install.sh changes                    — registry.sh is installed with existing lib/* loop
```

### What Builder Must NOT Do

1. Do NOT add `# POS_DEPS:` or `# POS_EXAMPLES:` to any existing tool in this PR (that's incremental migration, separate commits).
2. Do NOT change the `# POS:` header format or the em-dash convention.
3. Do NOT change `bin/pos` dispatch logic or `INTERACTIVE_CMDS`.
4. Do NOT add any new files beyond `lib/registry.sh`.
5. Do NOT modify the completion script (`completions/pos.bash`).
6. Do NOT refactor `lib/config-ui.sh` to use the registry.
7. Do NOT add a shebang to `lib/registry.sh` (it's a library, not executable).
8. Do NOT break `make gen && make check && make lint`.

[DECIDED]

---

## Decision 6: Risk Analysis

### Risk 1: `make gen` output changes break `git diff --exit-code` in CI

**Impact:** HIGH — blocks PRs.

**Cause:** Adding deps/examples parsing to gen-docs.sh changes the `tools` array format. The gen_* functions that consume this array will produce different output if any tool has the new headers. But since no tools have them yet, the output should be identical.

**Mitigation:** 
- The gen_* functions must produce **identical output** when no tools have `# POS_DEPS:` or `# POS_EXAMPLES:` headers.
- Test: run `make gen && git diff --exit-code` before committing. Zero diff = safe.
- The tools array format change (adding `$deps|$examples` fields) is internal to gen-docs.sh — the gen_* functions that render output must not use the new fields when they're empty.

### Risk 2: `reg_scan` performance degrades with many tools

**Impact:** LOW — current tool count is ~40.

**Cause:** Each tool file is read 4–6 times by `sed` during scan. For 40 tools, this is ~200 process spawns.

**Mitigation:**
- At current scale, scan completes in ~5ms. Even 100 tools would be ~15ms.
- If it ever becomes an issue, `reg_scan` could read each file once and parse all headers in a single `awk` pass. This is a future optimization, not needed now.

### Risk 3: Registry library conflicts with existing sourcing patterns

**Impact:** MEDIUM — could break tools that source both common.sh and registry.sh.

**Cause:** `registry.sh` declares guarded fallbacks for `log`, `warn`, `err` (same pattern as `config-ui.sh`). If both are sourced, the second source is a no-op because the functions already exist.

**Mitigation:**
- Use the same guarded-declaration pattern as `config-ui.sh`: `declare -F log >/dev/null || log() { ... }`.
- `registry.sh` does NOT define `run`, `spawn`, `confirm`, or any other common.sh functions.
- `registry.sh` does NOT call `err` during normal operation — only if `reg_scan` is called with an invalid directory (which won't happen in practice).

### Risk 4: `bin/pos-tree` migration breaks tree output

**Impact:** HIGH — visible to users.

**Cause:** The tree-building logic in `pos-tree` is tightly coupled to the current data collection. Replacing the collection loop might subtly change tree structure.

**Mitigation:**
- Keep the existing `add()`, `render()` functions unchanged.
- Replace ONLY the data-collection loop (lines 47–68) with registry calls.
- Test: run `bin/pos-tree` before and after, diff the output. Must be identical (for existing headers).
- The only visible change should be when a tool has `# POS_DEPS:` — deps appear in the tree.

### Risk 5: `pos <category>` performance regression

**Impact:** LOW — adds ~5ms per invocation.

**Cause:** `_pos_category_help()` would source and call `reg_scan` on every invocation.

**Mitigation:**
- Phase 2 only (not in this implementation).
- If needed, cache scan results in a temp file: `reg_scan` writes to `/tmp/.pos-registry-<hash>` and consumers check for freshness. This is premature — implement only if profiling shows a problem.

### Risk 6: New headers malformed, breaking parsing

**Impact:** LOW — malformed headers produce empty values, not crashes.

**Cause:** A tool author writes `# POS_DEPS` (missing colon) or `# POS_EXAMPLES foo bar` (missing pipe).

**Mitigation:**
- `reg_scan` uses strict pattern matching: `sed -n '/^# POS_DEPS: /{...}'`. Missing colon = no match = empty value. Graceful degradation.
- Add a lint WARN (not FAIL) for `# POS_DEPS:` lines without space-separated tokens.
- Add lint WARN for `# POS_EXAMPLES:` lines without `|` delimiter.
- Document the expected format clearly in DEV.md.

[DECIDED]

---

## Verification Plan

### Gate 1: Syntax

```bash
bash -n lib/registry.sh           # Must pass (no syntax errors)
bash -n scripts/gen-docs.sh       # Must pass (after modifications)
bash -n bin/pos-tree              # Must pass (after modifications)
```

### Gate 2: Gen Drift

```bash
make gen && git diff --exit-code   # Zero diff (no tools have new headers yet)
```

### Gate 3: Self-Consistency

```bash
make check    # Must pass (syntax + exec bits + doc/code sync + dispatch smoke)
```

### Gate 4: Convention Lint

```bash
make lint     # Must pass (0 FAIL, 0 WARN)
```

### Gate 5: Functional

```bash
# Registry works standalone
bash -c 'source lib/registry.sh; reg_scan; reg_list; reg_lookup docker ps desc'

# pos tree produces identical output
bin/pos-tree > /tmp/tree-before.txt
# ... apply changes ...
bin/pos-tree > /tmp/tree-after.txt
diff /tmp/tree-before.txt /tmp/tree-after.txt  # Must be empty

# pos category help works
bin/pos docker --help   # Must show docker tools
bin/pos network --help  # Must show network tools
```

### Gate 6: Regression

```bash
# All existing commands still dispatch
bin/pos --help
bin/pos docker --help
bin/pos network --help
bin/pos help network scan
```

---

## Implementation Guidance for Builder

### Step-by-step

1. **Create `lib/registry.sh`** (~180 lines). Start from the API spec in Decision 2. Use `lib/config-ui.sh` as a structural reference for the guarded fallbacks and source pattern.

2. **Update `scripts/gen-docs.sh`**. In the tools collection loop (lines 30–46):
   - Add `deps` and `examples` fields to the `tools` array format: `"$cat|$sub|$desc|$flags|$subcmds|$deps|$examples"`
   - Parse new headers with the same `sed` pattern as existing ones.
   - In `gen_tree()`, `gen_dispatch()`, `gen_filetable()`: add deps/examples columns ONLY when non-empty. Empty fields = identical output to current.

3. **Migrate `bin/pos-tree`**. Replace lines 47–68 (the file-scanning loop) with registry calls. Keep `add()`, `render()`, and the rest unchanged. Test that output is identical for existing tools.

4. **Update `templates/pos-tool.sh`**. Add `# POS_DEPS:` and `# POS_EXAMPLES:` to the header documentation block. Add them after the existing `# POS_FLAGS:` example.

5. **Update `DOC/DEV.md`**. In "Adding a New CLI Tool → Make it discoverable":
   - Document the new `# POS_DEPS:` and `# POS_EXAMPLES:` headers.
   - Explain when to use each (deps: list runtime binaries; examples: show 1–3 representative usages).

6. **Update `lib/registry.sh` line count** in `DOC/AGENT_Context_Project.md` filetable (the hand-maintained rows above the GEN marker).

7. **Run gates:** `make gen && make check && make lint`. Verify 0 FAIL, 0 WARN.

### Critical Constraints

- `lib/registry.sh` must NOT have a shebang (library, not executable).
- `lib/registry.sh` must be added to the `lib_names` list in `install.sh` Phase 2 (line 143).
- `reg_scan` must set `LC_ALL=C` for deterministic sort.
- gen-docs.sh changes must produce zero diff when no tools have new headers.
- `pos-tree` output must be byte-identical before/after migration (for existing headers).

---

## Open Questions (for Orchestrator)

1. Should `pos <category> --help` (in `bin/pos`) be migrated in this phase or deferred to Phase 2? **Recommendation: defer to Phase 2** — lower risk, and the category help is already working.

2. Should the lint gate enforce that `# POS_DEPS:` tokens are valid binary names? **Recommendation: WARN only, not FAIL** — some deps might be shell builtins or paths, not just binary names.

3. Should `reg_scan` support a `--cached` mode? **Recommendation: no, not yet** — premature optimization for 40 tools.

---

*Report written by Architect agent. Next recommended agent: **Builder** (to implement the approved scope).*
