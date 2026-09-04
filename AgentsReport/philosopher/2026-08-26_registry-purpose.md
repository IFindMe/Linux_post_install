# Philosopher Analysis: Self-Describing Command Registry for POS

**Date:** 2026-08-26
**Author:** Philosopher (big-pickle)
**Status:** ANALYSIS_READY

---

## TL;DR

**Purpose:** Make POS introspectable — a single source of truth for command metadata that feeds all consumers (tree, help, menu, config, dashboard) without duplication.

**Core tension:** The project already has a lightweight registry (POS headers + gen-docs.sh). The real value isn't building a new system, but **centralizing the consumption** of what exists. The risk is building a framework that's harder to maintain than the current scattered approach.

**Key insight:** This is not about making commands "self-describing" — they already are via `# POS:` headers. This is about making POS itself able to answer "what can I do?" as a unified system, not as 40+ disconnected scripts.

**Recommendation:** Build a **query API** over existing metadata, not a new registry framework. The soul is introspection, not abstraction.

---

## Step 1: What Problem Actually Exists?

The current state is already a registry:

- Every tool declares `# POS: <cat> <cmd> — <desc>`
- Many declare `# POS_SUBCMDS:` (subcommands/actions)
- Many declare `# POS_FLAGS:` (flags for completion)
- Some declare `# POS_CONFIG:` (config scopes)
- `make gen` regenerates docs/completions from these headers
- `pos tree` derives hierarchy from filenames + headers
- `pos <category> --help` shows tool descriptions from headers

**What's missing is not a registry, but a shared query mechanism.** Today:

- `pos tree` reimplements header parsing (pos-tree does its own scan)
- `pos <category> --help` reimplements header parsing (pos dispatcher does its own scan)
- `make gen` reimplements header parsing (gen-docs.sh does its own scan)
- `pos config` reimplements header parsing (config-ui.sh does its own scan)
- A future dashboard would need to reimplement header parsing again

Each consumer independently reads the same files and extracts the same data. That's the duplication: **not the metadata itself, but the logic that reads it.**

---

## Step 2: Why Not Just Good --help?

Good `--help` on each tool is necessary but insufficient. It serves:

- **Single-tool consumers** (a human running `pos network download --help`)
- **No cross-cutting concerns** (can't list all tools, find dependencies, show unified menu)

A registry enables:

- **System-wide queries**: "What commands exist?" "What depends on aria2c?" "What has config?"
- **Programmatic consumers**: Menu generation, dashboard aggregation, config discovery
- **Single source of truth**: Add metadata once, appears everywhere (tree, help, menu, config)

The soul isn't "each tool describes itself" (that's already true). The soul is **"POS as a system can describe itself."**

---

## Step 3: The Soul — Introspection

What does a self-describing POS enable that wasn't possible before?

1. **POS can answer "what can I do?"** — not via scattered `--help` calls, but as a unified query. A menu, a dashboard, a Telegram bot, or a human can ask "show me everything" and get a coherent answer.

2. **POS can answer "what do I need?"** — dependencies are declared. A dashboard can show "these 3 tools won't work without aria2c." A menu can gray out unavailable tools.

3. **POS can answer "what can I configure?"** — config scopes are discoverable. A unified config UI can show all configurable tools without hardcoding them.

4. **Adding a new tool is one step** — write the tool, add its headers, done. No updating tree definitions, menu code, dashboard configs, help text in multiple places.

The soul is **making POS a self-aware system rather than a collection of scripts with documentation.**

---

## Step 4: Risks of Over-Engineering

The spec explicitly warns against this: "Do NOT build a giant abstraction layer." But the risk is real:

1. **Framework trap**: Building `CommandBase`, `CommandFactory`, etc. that every tool must conform to. This would require rewriting 40+ tools and violating the "existing commands must keep working" principle.

2. **Metadata burden**: Requiring every tool to define every field (dependencies, examples, arguments). This breaks the "progressive metadata" principle — simple tools should stay simple.

3. **Staleness risk**: A separate registry file that must be kept in sync with the actual tools. This is worse than the current system where metadata lives with the implementation.

4. **Complexity creep**: The current system is simple (headers + gen-docs.sh). A "proper" registry could become a maintenance burden that's harder to understand than the problem it solves.

---

## Step 5: Minimum Viable Registry

The minimum that delivers real value:

1. **Centralized query API** — A single function (or small set) that parses all tool headers once and provides lookup/iteration. This eliminates the per-consumer reimplementation.

2. **Dependency metadata** — Add `# POS_DEPS:` header (optional) so the system can answer "what tools need aria2c?" This is genuinely useful for dashboards and health checks.

3. **Examples metadata** — Add `# POS_EXAMPLES:` header (optional) so help can show curated usage patterns, not just `--help` output.

4. **Shared consumption** — `pos tree`, `pos <category> --help`, `make gen`, and future consumers all use the same query API instead of reimplementing header parsing.

What this does NOT include:

- A separate registry file (metadata stays in tool headers)
- Required fields beyond name/description
- Abstract base classes or framework patterns
- Rewriting existing tools

---

## Step 6: What Should NOT Be Built

Explicitly NOT:

1. **A separate registry database** — Metadata stays in tool headers (`# POS:` etc.). A separate file would create synchronization problems.

2. **Abstract base classes** — No `CommandBase`, `AbstractCommand`, `CommandFactory`. Tools are bash scripts, not OOP objects.

3. **Required metadata fields** — Tools should not need to define arguments, examples, or dependencies. These are optional enhancements.

4. **A new configuration language** — No YAML/JSON/TOML for tool metadata. The current comment-header format is simple and works.

5. **A monolithic registry manager** — No single large script that owns all metadata. The query API should be a small library (like `lib/common.sh`) that tools can source if needed.

6. **Migration pressure** — Existing tools should not need rewriting to "conform" to the registry. The registry should read what exists, not demand what should exist.

---

## Step 7: Recommendations

### For the Architect

1. **Start with the query API** — Build a `lib/registry.sh` (or similar) that provides:
   - `registry_list` — list all tools with metadata
   - `registry_get <tool>` — get metadata for a specific tool
   - `registry_find <criteria>` — find tools by dependency, category, etc.
   - `registry_has_config` — list tools with config scopes

2. **Extend existing headers** — Add `# POS_DEPS:` and `# POS_EXAMPLES:` as optional headers. Don't require them.

3. **Refactor consumers** — Update `pos tree`, `pos <category> --help`, `make gen` to use the shared API instead of reimplementing parsing.

4. **Don't touch tool implementations** — Tools keep their current structure. The registry reads headers; it doesn't modify tools.

### For the Philosopher's Soul Check

The soul of this feature is **introspection** — making POS a self-aware system. If the implementation makes POS harder to understand, maintain, or extend, it has failed. If it makes adding new tools easier and cross-cutting queries possible, it has succeeded.

---

## Open Questions

1. **Where does the query API live?** `lib/registry.sh`? Inside `bin/pos`? A standalone script that `make gen` calls?

2. **Should `pos tree` be refactored to use the API?** Or is the current implementation (scanning headers directly) simpler and sufficient?

3. **How much of the current `gen-docs.sh` logic should move to the registry API?** The script already parses headers — should it become the registry, or should the registry be separate?

4. **Is `# POS_DEPS:` the right header name?** Could be `# POS_REQUIRES:` or `# POS_NEEDS:` for clarity.

5. **Should examples be inline in headers or in a separate file?** Headers are terse; examples might be better in `DOC/howto/*.md` (which already exists).

---

## Assumptions

1. The current header format (`# POS:`, `# POS_SUBCMDS:`, etc.) is the right abstraction level. It's simple, proven, and works.

2. The problem is primarily about **consumption duplication**, not **metadata inadequacy**. The metadata exists; the shared access pattern doesn't.

3. The user wants this to be **incremental** — not a big-bang rewrite. The spec says "existing commands must keep working" and "incremental migration approach."

4. The soul is **introspection**, not **abstraction**. The goal is making POS self-aware, not building a framework.

---

## Decision Principles

When in doubt, ask:

1. **Does this make adding new tools easier?** If not, why build it?
2. **Does this reduce duplication?** If it adds more code than it removes, it's over-engineering.
3. **Does this maintain simplicity?** If a new contributor can't understand the registry in 5 minutes, it's too complex.
4. **Does this serve the soul?** If it doesn't make POS more self-aware, it's not serving the purpose.

---

## Handoff Recommendation

**Status:** ANALYSIS_READY

**Discovery summary:** The project already has a lightweight registry (POS headers + gen-docs.sh). The real value isn't building a new system, but centralizing the consumption of what exists. The soul is introspection — making POS a self-aware system that can answer "what can I do?" as a unified query.

**Philosophy document:** Not created (this is a feature analysis, not a new project). The design spec already captures the purpose well.

**Key insights:**
1. The problem is consumption duplication, not metadata inadequacy
2. The soul is introspection, not abstraction
3. The minimum viable registry is a shared query API over existing headers
4. The risk is building a framework that's harder to maintain than the current system

**Open questions:**
- Where does the query API live? (lib/registry.sh vs. inside bin/pos)
- Should gen-docs.sh become the registry, or should it be separate?
- Is the current header format the right abstraction level?

**Assumptions made:**
- The current header format is the right abstraction level
- The problem is consumption duplication, not metadata inadequacy
- The user wants incremental change, not a big-bang rewrite

**Recommended next agent:** Architect

**Reason:** The philosophical analysis is complete. The purpose is clear: introspection via a shared query API. The Architect can now design the implementation details (where the API lives, how consumers refactor, what new headers to add).

**Changes made by Philosopher:**
- Analysis written to `./AgentsReport/philosopher/2026-08-26_registry-purpose.md`
