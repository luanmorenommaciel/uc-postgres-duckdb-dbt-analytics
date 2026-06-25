# Cross-Tool Portability

> How agents-kbs-tech-stack produces a single source of truth under `.claude/` and emits cooperating-tool shims so the same agent layer works in Claude Code, Cursor, GitHub Copilot, Codex, and any future AGENTS.md-aware tool.

## TL;DR

| You author | The skill emits | Tool that reads it |
|------------|-----------------|--------------------|
| `.claude/agents/*.md` | (same files) | Claude Code |
| `.claude/kb/**` | (same files) | Claude Code, closers at runtime |
| `.claude/doctrine.yaml` | (same file) | Any tool that honors the portable contract |
| (derived) | `AGENTS.md` at repo root | Codex, Aider, OpenAI Operator, any AGENTS.md-aware tool |
| (derived) | `.cursor/rules/agents-kbs-tech-stack.mdc` | Cursor |
| (derived) | `.github/copilot-instructions.md` | GitHub Copilot |

You write to one place. Three shims point back at it.

---

## The AGENTS.md convention

`AGENTS.md` is a community convention promoted by the Linux Foundation's Agentic AI Foundation as a vendor-neutral way for AI coding tools to discover a repository's agent layer. As of mid-2026, 20+ tools honor it, including:

- Codex (OpenAI)
- Aider
- Cursor (via mdc fallback)
- Continue.dev
- GitHub Copilot Chat (via `.github/copilot-instructions.md` cross-link)
- OpenAI Operator
- Cline / Roo Code
- ChatGPT projects with repo connectors

The contract is minimal: a Markdown file at the repository root named exactly `AGENTS.md`. Its conventional sections are `## Scope`, `## Agents`, `## Knowledge Base`, and `## Conventions`. Tools that don't recognize the convention treat it as a normal Markdown file — no harm done.

agents-kbs-tech-stack's `AGENTS.md` is generated, not hand-written. Its content reflects the *canonical* state of `.claude/agents/` (filesystem walk) and `.claude/kb/_index.yaml` (parsed YAML). Every entry in the Agents table corresponds to a file under `.claude/agents/`; every entry in the KB table corresponds to a domain in `_index.yaml`.

---

## What gets emitted, and where

### 1. `<repo>/AGENTS.md`

The cross-tool index. Sections:

- **`# {PROJECT_NAME} — AGENTS.md`** — title line uses the `project:` field from `.claude/kb/_index.yaml`.
- **`## Scope`** — boilerplate describing the agent layer's shape (architect / developer / optional troubleshooter / closer).
- **`## Agents`** — table of every `.md` file under `.claude/agents/`, including:
  - Agent name (from frontmatter `name:`)
  - Role (inferred from filename suffix: `-architect`, `-developer`, `-troubleshooter`, or the closer family)
  - First sentence of the frontmatter `description:`
  - Link back to the source file
- **`## Knowledge Base`** — table of every domain under `domains:` in `_index.yaml`, including:
  - Domain slug + display name
  - Description
  - Link to the domain's `quick-reference.md`
- **`## Conventions`** — pointer to `.claude/doctrine.yaml` and back-references to the skill.
- **Footer** — generator stamp with the emission date.

### 2. `<repo>/.cursor/rules/agents-kbs-tech-stack.mdc`

A Cursor MDC rule with:

- `description`: "Project-wide agents and KB managed by agents-kbs-tech-stack"
- `globs: "**/*"`
- `alwaysApply: false` — Cursor pulls it in by content match, not unconditionally

Body points at `.claude/agents/` and `.claude/kb/` as the authoritative sources. Body is short on purpose — Cursor's MDC system is best used as a *pointer*, not as a duplicate of the agent layer.

### 3. `<repo>/.github/copilot-instructions.md`

The minimum viable Copilot file. One paragraph, pointing at `AGENTS.md`. Copilot Chat reads this file on every interaction; keeping it tiny avoids drowning out the actual instructions in `.claude/` and `AGENTS.md`.

---

## When to re-emit

Run `scripts/emit-cross-tool.sh` after **any** of the following:

| Trigger | Why |
|---------|-----|
| You added a tech (`scaffold.sh` ran) | New agents in `.claude/agents/`, new domain in `_index.yaml` — both tables in AGENTS.md are now stale. |
| You removed a tech | Same as above, in reverse. |
| You added the troubleshooter role to an existing tech | A new agent file appeared — the Agents table needs the row. |
| You installed closers (`install-closers.sh`) | Three new closer agents appeared. |
| You renamed the project (`project:` in `_index.yaml`) | AGENTS.md title changed. |
| You bumped doctrine (`.claude/doctrine.yaml`) | The conventions pointer should reflect the new version on the next emission. |
| You're onboarding a new tool that reads AGENTS.md | Make sure the latest state is on disk. |

Re-emission is **idempotent and destructive**: the three target files are overwritten unconditionally. That's intentional — they're generated artifacts, not user-authored. If you find yourself wanting to "preserve hand-edits" to AGENTS.md, that's the smell that the underlying source (`.claude/`) is missing whatever you tried to write into the shim.

---

## How the three files stay in sync

There is exactly **one** source of truth: `.claude/`. Every other file is a projection.

```
.claude/agents/*.md           ─┐
.claude/kb/_index.yaml        ─┼─► emit-cross-tool.sh ─► AGENTS.md
.claude/kb/<tech>/**          ─┘                       ─► .cursor/rules/agents-kbs-tech-stack.mdc
                                                       ─► .github/copilot-instructions.md
```

The script reads `.claude/` and writes the three shims. It never goes the other direction. If a downstream tool (Cursor, Copilot) "learns" something the agents should know, that learning must flow back into `.claude/kb/` or `.claude/agents/`, then the shims re-emit.

This shape has three nice properties:

1. **No drift surface.** The shims can't fall out of sync with each other because they share a single upstream.
2. **Reversibility.** Deleting the shims and re-running `emit-cross-tool.sh` reproduces the cross-tool surface byte-for-byte (up to the embedded date).
3. **Skill upgradability.** When agents-kbs-tech-stack v0.4 changes the shim format, every consumer repo gets the new format by re-running one script — no per-repo migration.

---

## Anti-patterns

| Don't | Why | Do instead |
|-------|-----|------------|
| Hand-edit `AGENTS.md` | It's generated. Your edit dies on the next re-emit. | Edit `.claude/agents/<name>.md` frontmatter, or add the missing fact to `.claude/kb/<tech>/`. Then re-emit. |
| Hand-edit `.cursor/rules/agents-kbs-tech-stack.mdc` | Same — generated. | If the mdc body should change for everyone, edit `templates/cursor-rules.mdc.tpl` in this skill and re-emit. |
| Hand-edit `.github/copilot-instructions.md` | Same. | If the Copilot file should grow project-specific guidance, *add a second file* (e.g., `.github/copilot-project.md`) and reference it from `AGENTS.md`. Keep the generated file minimal. |
| Skip re-emission after adding a tech | AGENTS.md silently lies about which agents exist. Downstream tools won't pick up the new tech. | Add `emit-cross-tool.sh` to your post-scaffold checklist (or wire it into a Makefile target). |
| Treat `AGENTS.md` as documentation for humans | It's machine-readable. Humans read `.claude/` and the per-tech KBs. | Use `README.md` for human onboarding. `AGENTS.md` is for tools. |
| Make `.claude/doctrine.yaml` Claude-Code-specific | Doctrine is the *portable* contract; it's the reason cross-tool emission works. | Keep doctrine vendor-neutral (Bash boundary, thresholds, closer-hook). Per-tool tweaks live in the tool's own config. |

---

## What this is not

- **Not a runtime bridge.** This skill does not synchronize agent *behavior* across tools at runtime. Each tool still runs its own model with its own context window. The cross-tool layer is a discovery and grounding shim, not a federation protocol.
- **Not a replacement for tool-specific config.** Cursor's `.cursor/rules/*.mdc` system is rich; the shim is the minimum that points at the canonical source. If a project needs Cursor-specific behavior, add additional mdc files alongside the generated one (and don't let them duplicate `.claude/` content).
- **Not versioned per-tool.** The shims don't carry a "for Cursor v0.x" version. The convention is stable enough that tool versions don't matter for the pointer use case. If a tool changes its config format incompatibly, agents-kbs-tech-stack bumps `templates/<tool>.tpl` and the next emission picks it up.

---

## References

- [AGENTS.md convention site](https://agents.md/) — community spec
- Linux Foundation Agentic AI Foundation — convention sponsor
- `templates/AGENTS.md.tpl` — the template `emit-cross-tool.sh` renders
- `templates/cursor-rules.mdc.tpl` — Cursor shim source
- `templates/copilot-instructions.md.tpl` — Copilot shim source
- `scripts/emit-cross-tool.sh` — the emitter
- `.claude/doctrine.yaml` — the portable agent contract that makes cross-tool emission meaningful
