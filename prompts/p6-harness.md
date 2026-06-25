# Converge · Pass 6 — Harness

**Engine:** the `agents-kbs-tech-stack` skill — scaffolds the control layer fitted to the tasks.
**Inputs:** `tasks/*` (they name the tech they need) · the two plans · the repo.
**Output:** `.claude/` — tech agents + KBs + rules + `CLAUDE.md` — plus emitted `AGENTS.md` / Cursor / Copilot mirrors.
**Gate:** the control layer stands — every tech a task needs has an agent and a grounded KB, and the cross-tool files are emitted from `.claude/` source.

Three steps: **read the tasks' needs → scaffold exactly those → emit cross-tool.**

> Teaching note: Harness comes AFTER Tasking by design. The tasks are the requirements; the harness is fitted to them — we scaffold only the tech the tasks actually invoke. For this repo that's dbt and DuckDB (and MCP/FastAPI for the serving tasks). No Dagster, no CrewAI — nothing the tasks don't ask for. Build the control layer to the work, not the work to the control layer.

---

## Step 1 · Read the tasks' needs

```text
Read every file under tasks/. Inventory the technologies they invoke and the
shape of work each demands — which need PLANNING (architecture, trade-offs, no
code) versus SHIPPING (models, endpoints, tests). For this repo expect: dbt and
DuckDB for the medallion tasks, FastAPI/MCP for the serving tasks. List the
distinct techs and, per tech, whether the tasks need an architect, a developer,
or both. Do not invent techs no task asks for.
```

## Step 2 · Scaffold exactly those tech agents + KBs

```text
Using agents-kbs-tech-stack, scaffold .claude/ for exactly the techs you found:

- A tech agent per tech the tasks need (architect for the planning ones,
  developer for the shipping ones — dbt, duckdb, and mcp/fastapi).
- A KB per tech under .claude/kb/<tech>/, grounded in the official docs (cite the
  source-of-truth URL in each KB doc; leave TODO blocks where a layer isn't built
  yet).
- The universal closers (code-reviewer, code-simplifier, code-documenter) that
  ground in those KBs at runtime.
- The rules and CLAUDE.md: how agents work this repo, the raw.*→gold seam, the
  one-way Postgres→DuckDB dependency, the "eval passes = done" contract.

Scaffold only what the tasks require. Nothing speculative.
```

## Step 3 · Emit cross-tool

```text
Emit the cross-tool mirrors from the .claude/ source: AGENTS.md, the Cursor rules
(.cursor/rules/*.mdc), and the Copilot instructions (.github/copilot-instructions.md).
These are GENERATED — never hand-edited. The .claude/ source is the single source
of truth; the mirrors are re-emitted from it. Confirm the emit ran clean and the
mirrors agree with the source.
```

---

## Gate — confirm before leaving Pass 6

- [ ] Every tech a task invokes has an agent (architect / developer as the work demands).
- [ ] Each tech has a KB under `.claude/kb/<tech>/`, grounded in official docs with cited sources.
- [ ] The universal closers exist and ground in the KBs at runtime.
- [ ] `CLAUDE.md` + rules encode the seam (raw.*→gold), the one-way dependency, and "eval passes = done".
- [ ] Cross-tool mirrors (`AGENTS.md`, Cursor, Copilot) are EMITTED from `.claude/` — not hand-edited.
- [ ] Nothing scaffolded that no task asked for (no Dagster, no CrewAI).

When these hold, the control layer stands and feeds **Pass 7 — Execution**, where the tasks get built against it.

---

### Notes

- **Tasking-before-Harness is the deliberate order.** The tasks named what they need (tech + eval) without the harness existing; Pass 6 fits the harness to that. Building the harness first would mean guessing the techs — a forward dependency avoids the circularity.
- **Fit, don't pad.** Scaffold dbt + duckdb (+ mcp/fastapi) because the tasks invoke them. Resist adding agents for techs out of scope for this repo — an unused agent is drift waiting to happen.
- **KB quality is the lever.** The closers and tech agents are only as sharp as the KBs they ground in. Populate the cited docs; leave honest `TODO` blocks where a layer isn't built yet rather than bluffing.
- **Generated files are not hand-edited.** `AGENTS.md` / Cursor / Copilot are emitted. Edit `.claude/` source and re-emit; reconcile any stray hand-edit back into source.
