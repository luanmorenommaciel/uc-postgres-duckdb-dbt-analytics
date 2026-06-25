---
name: agents-kbs-tech-stack
description: |
  Scaffold a project's tech-stack agent layer from a curated menu. For each picked
  tech, produces a paired (architect + developer) agent + a full KB tree. Also
  installs three universal closers (code-reviewer, code-simplifier, code-documenter)
  that ground in every tech KB via the closer-hook protocol. v0.3.0 adds a
  quality-gate pass that lints scaffolded output for drift, a cross-tool
  emission step that publishes AGENTS.md + Cursor rules + Copilot instructions
  alongside .claude/, and a tunable doctrine.yaml that captures portable
  defaults (Bash boundary, threshold floors, closer-hook protocol) so other
  tools (Codex, Cursor, Copilot) inherit the same agent contract. Sibling to
  agents-kbs-fleet — that one scaffolds project-specific specialists, this one
  scaffolds portable tech specialists. Use when bootstrapping a new repo's
  technology coverage or adding a new tech to an existing fleet.
---

# agents-kbs-tech-stack — Build Tech-Stack Agent Layers

> **Identity:** Meta-skill that scaffolds (architect + developer) agent pairs per tech, plus three universal closers.
> **Domain:** Tech specialization, role splitting (planning vs implementation), closed engineering loop.
> **Default Threshold:** 0.90

---

## What this skill produces

For each tech the user picks from the curated menu:

```text
<target-repo>/.claude/
├── agents/
│   ├── <tech>-architect.md         # Planning, trade-offs, ADRs — no Bash
│   └── <tech>-developer.md         # Code, tests, fixes — has Bash
└── kb/
    ├── _index.yaml                 # Tech registered as a domain block
    └── <tech>/                     # Full KB tree, seeded from the menu
        ├── quick-reference.md
        ├── concepts/×3
        ├── patterns/×3
        └── reference/×2
```

Plus, exactly once per repo:

```text
<target-repo>/.claude/agents/
├── code-reviewer.md                # Universal pre-merge reviewer
├── code-simplifier.md              # Universal refactor-for-clarity agent
└── code-documenter.md              # Universal docstring/README/ADR writer
```

The closers are **tech-agnostic by interface, tech-aware by grounding**: at runtime, each closer reads `kb/_index.yaml`, detects the file's language from its extension, and loads the matching tech KB. See [`references/closer-hook-protocol.md`](references/closer-hook-protocol.md).

**What this skill does NOT do:** rules, slash commands, workflow pipelines, LESSONS files, MCP server code, CLAUDE.md authoring, global agent installs, or writes outside `<target-repo>/.claude/`.

---

## When to invoke this skill

Trigger conditions:

- User asks to "scaffold tech specialists", "add a React architect", "build the agent fleet for this stack"
- User is starting a new repo and wants the tech-coverage layer from day one
- User wants to add a tech to an existing repo's fleet (the skill is additive)
- The skill performs a quick repo-shape check first and may suggest a sibling skill (`agents-kbs-fleet`, `caw-scaffold`) if the repo looks code-light — you can override.

Skip if:

- User wants project-domain specialists (e.g., `graph-builder` for *this specific* graph view) — use `agents-kbs-fleet` (v1) instead.
- User wants a single Skill + Agent + MCP capability — use `caw-scaffold`.
- The desired tech is not in `menu/techs.yaml` — first add it to the menu (see `references/tech-menu-curation.md`), then run the skill.

---

## Workflow

### Phase 0 — Repo-shape check (advisory, ~1 second)

Before asking about tech picks, run `scripts/detect-code-light.sh` against `TARGET_REPO`. The script always exits 0 and prints one token on stdout: `CODE_HEAVY` or `CODE_LIGHT`.

- **CODE_HEAVY (default case, ~95%)**: proceed silently to Phase 1. Do not mention the check to the user — there is nothing interesting to say.
- **CODE_LIGHT (<30% code files among classifiable files)**: surface ONE `AskUserQuestion` with the stats line in the prompt and four options, before showing the menu:
  1. **Proceed anyway** — "I'm scaffolding for code I'll write soon" (this is option 1 by design — the knowing user picks instantly).
  2. **Use `agents-kbs-fleet` instead** — for project-specific specialists (KB-shaped repos).
  3. **Use `caw-scaffold` instead** — for a single Skill + Agent + MCP capability.
  4. **Abort** — no scaffolding wanted.

  Options 2/3/4 exit the skill cleanly with a one-line invocation hint for the chosen sibling. Option 1 continues to Phase 1 with no further friction.

The detector NEVER blocks. If it fails to run (no python3, permission errors), the skill proceeds as if CODE_HEAVY. Phase 0 only ever speaks up when there's a real signal — silent on the 95%, helpful on the 5%.

If the user proceeded under CODE_LIGHT, the Phase 5 report gains one extra line at the top: `Note: scaffolded against a code-light repo (X% code). Populate KB content as you write the code.`

### Phase 1 — Project + menu pick

Ask the user, in order:

1. **`PROJECT_NAME`** — short repo slug.
2. **`PROJECT_DESCRIPTION`** — one sentence (used in KB index).
3. **`TARGET_REPO`** — absolute path (default: current dir).
4. **Pick techs from the menu** — show the 10 curated techs from `menu/techs.yaml` via a multi-select `AskUserQuestion`. User picks 1–N.

No per-tech interview. The menu *is* the customization — each entry already declares thresholds, MCPs, KB seeds, capabilities, and missions.

### Phase 2 — Preview & confirm

Print the file tree that will be written:

```text
For N picked techs:
  - 2N tech agents (<tech>-architect.md, <tech>-developer.md)
  - N KB trees (quick-reference + concepts/×3 + patterns/×3 + reference/×2)
  - <new domains> appended to .claude/kb/_index.yaml

If closers absent:
  - 3 closer agents (code-reviewer, code-simplifier, code-documenter)
```

Single confirm gate via `AskUserQuestion`: scaffold / revise / abort.

### Phase 3 — Scaffold

For each picked tech, invoke `scripts/scaffold.sh` with `TARGET_REPO`, `PROJECT_NAME`, `PROJECT_DESCRIPTION`, and `TECH=<slug>` as env vars. The script:

1. Loads the tech's config from `menu/techs.yaml`.
2. Renders `templates/architect.md.tpl` and `templates/developer.md.tpl` with menu-supplied values.
3. Seeds the KB tree using the menu's seed slugs.
4. Updates `kb/_index.yaml` (additive — re-runs never clobber).

After all techs, invoke `scripts/install-closers.sh` once. Each closer is copied as-is (no substitution — closers are tech-agnostic by content; they discover techs at runtime).

### Phase 3.5 — Quality gate (advisory by default)

After scaffold completes, the skill invokes `scripts/quality-gate.sh` against the target repo. The gate runs local alignment checks (role boundaries, placeholder leaks) and, if available, dispatches `/kimi:review` for a cold-eyes pass. Findings are classified BLOCKER / IMPORTANT / NIT and surfaced in the Phase 4 report. To enforce gating (non-zero exit on BLOCKER), invoke the gate manually with `--strict`. If BLOCKERs surface, you can offer the user a single option: invoke `/codex:rescue` with the gate findings as input for an automated fix pass.

- **Default mode** is advisory: the gate always exits 0 and lets the user decide whether to act on the findings.
- **`--strict` mode** exits 7 when one or more BLOCKER findings are present — wire this into CI when you want the build to fail on role-boundary violations or placeholder leaks.
- **`/codex:rescue` rescue path**: when BLOCKER findings are reported, pipe the verdict block plus per-file details into `/codex:rescue` so an external rescue agent can patch role boundaries, missing frontmatter, or leaked placeholders without the user round-tripping a hand fix.

See [`references/quality-gate-protocol.md`](references/quality-gate-protocol.md) for the full check inventory, severity definitions, and the kimi/codex integration contract.

### Phase 4 — Cross-tool emission (always)

After the quality gate, invoke `scripts/emit-cross-tool.sh` once. This translates the scaffolded `.claude/` surface into the well-known formats consumed by other agentic tools, so a single source of truth (the Claude skill output) drives every tool the team uses:

```text
<target-repo>/
├── .claude/                         # owned by this skill (canonical)
├── AGENTS.md                        # Codex / OpenAI Agents — repo root
├── .cursor/
│   └── rules/
│       ├── agents.mdc               # always-applied rules from doctrine.yaml
│       └── <tech>.mdc               # one per tech, scoped via Cursor globs
└── .github/
    └── copilot-instructions.md      # GitHub Copilot repo-level instructions
```

The emitter:

1. Reads `kb/_index.yaml` + `doctrine.yaml` + every `agents/*.md` frontmatter.
2. Renders `AGENTS.md` with one section per agent — name, threshold, tools, mission, and a Quick Reference pointer to the KB.
3. Renders one `.cursor/rules/<tech>.mdc` per tech (scoped via the menu's `cursor_globs`) and one `.cursor/rules/agents.mdc` that mirrors the doctrine (Bash boundary, threshold floors, closer-hook protocol).
4. Renders `.github/copilot-instructions.md` as a flat, prose digest of the doctrine + per-tech do/don't summaries.

Emission is **idempotent and additive**: existing emitted files are diffed; if the user has hand-edited a file, the emitter writes a `.proposed` sibling and prints a NOTE line rather than clobbering.

If `scripts/refresh-doctrine.sh` has never run, `doctrine.yaml` is auto-created from the bundled default. Editing `doctrine.yaml` and re-running `emit-cross-tool.sh` is the supported way to retune the cross-tool surface without re-scaffolding.

### Phase 5 — Report

```text
Scaffolded N techs + closers into <target>/.claude/

| Tech | Architect threshold | Developer threshold | MCPs |
|------|--------------------|--------------------|------|
| ... | ... | ... | ... |

Universal closers: ✓ code-reviewer | ✓ code-simplifier | ✓ code-documenter

Next steps:
1. Open each tech's KB entries and populate the `<!-- TODO -->` blocks.
2. Open each architect's Decision Frameworks section and add 2–3 trade-off matrices.
3. Open each developer's Implementation Patterns section and add 2–4 production code samples.
4. The closers ground in the tech KBs at runtime — content quality there determines closer sharpness.
```

---

## Self-containment guarantee

The skill writes nothing outside `<target-repo>/.claude/` **except** the four cross-tool emission files at well-known locations consumed by sibling agentic tools. No CLAUDE.md changes, no source code touched, no git ops, no network calls. Drop the bundle in offline, run offline.

The complete list of paths v0.3.0 may write to outside `.claude/`:

| Path | Owner / consumer | Why |
|------|------------------|-----|
| `<target-repo>/AGENTS.md` | Codex, OpenAI Agents SDK, taskship, anthive | Repo-root agent contract — well-known convention |
| `<target-repo>/.cursor/rules/agents.mdc` | Cursor | Always-applied doctrine rules |
| `<target-repo>/.cursor/rules/<tech>.mdc` | Cursor | Per-tech rules, scoped via Cursor globs |
| `<target-repo>/.github/copilot-instructions.md` | GitHub Copilot | Repo-level Copilot instruction file |

Every other file the skill produces still lands under `.claude/` (agents, KBs, `doctrine.yaml`, `_index.yaml`). The emitter is the **only** code path that crosses the boundary, it is **idempotent**, and it never overwrites a hand-edited file — it writes a `.proposed` sibling and prints a NOTE instead.

---

## Validation System (Agreement Matrix)

The skill itself uses the Agreement Matrix the agents it generates use:

```text
                    │ MCP AGREES     │ MCP DISAGREES  │ MCP SILENT     │
────────────────────┼────────────────┼────────────────┼────────────────┤
KB HAS PATTERN      │ HIGH: 0.95     │ CONFLICT: 0.50 │ MEDIUM: 0.75   │
KB SILENT           │ MCP-ONLY: 0.85 │ N/A            │ LOW: 0.50      │
```

**KB** = `references/` (this skill).
**MCP** = optional; skill works fully offline.

---

## Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Approach |
|--------------|----------------|------------------|
| Skipping menu, freeform tech entry | Quality control disappears; menu is the curation layer | Add the tech to `menu/techs.yaml` first, then scaffold |
| Filling architect body with code blocks | Architects plan; code belongs in developer | Decision frameworks + trade-off matrices only |
| Filling developer body with high-level decisions | Developers ship; decisions belong in architect | Production patterns + anti-patterns only |
| Skipping closer install on the first run | Breaks the closed-loop guarantee | Always install closers when missing |
| Overwriting customized closers on re-run | Destroys user edits silently | `install-closers.sh` always skips existing files |
| Adding a tech to the menu without recommended MCPs | Agents won't ground well | Every menu entry must declare ≥1 MCP |

---

## Relationship to other skills

| Skill | Unit of scaffolding | When |
|-------|---------------------|------|
| `caw-scaffold` | One Skill + One Agent + One MCP (a Triad) | New reusable capability |
| `agents-kbs-fleet` (v1) | Project-specific specialist (e.g., `payments-parser`, `graph-builder`) | Domain-coupled work in this repo |
| `agents-kbs-tech-stack` (this) | Tech specialist pair (architect + developer) + universal closers | Stack coverage portable across projects |

Most real projects end up with all three layers. Use them together.

---

## References

- [`references/architect-vs-developer.md`](references/architect-vs-developer.md) — why the role split, what each owns
- [`references/closer-hook-protocol.md`](references/closer-hook-protocol.md) — how closers ground in tech KBs at runtime
- [`references/tech-menu-curation.md`](references/tech-menu-curation.md) — how to add a new tech to the menu
- [`runbooks/pick-your-stack.md`](runbooks/pick-your-stack.md) — end-to-end walkthrough (v0.3.0)
- [`runbooks/upgrade-v02-to-v03.md`](runbooks/upgrade-v02-to-v03.md) — migrating an existing v0.2 scaffold to v0.3.0

External (linked, not duplicated):

- v1's [`agent-anatomy.md`](../agents-kbs-fleet/references/agent-anatomy.md) — universal section rationale
- v1's [`kb-taxonomy.md`](../agents-kbs-fleet/references/kb-taxonomy.md) — concepts/patterns/reference/quick-reference taxonomy

---

## Remember

> **"Architect plans. Developer ships. Closers polish. Stack covered."**

**Mission:** Bootstrap a project's tech-coverage agent layer in 5 minutes, with the closed engineering loop wired in by default — and in v0.3.0, with cross-tool emission and a quality gate that keep Claude, Codex, Cursor, and Copilot reading the same agent contract.

---

*agents-kbs-tech-stack v0.3.0.*
