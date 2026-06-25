# Converge — the process runbook

The facilitator's front door to `prompts/`. Converge is a method for **compiling
intent into autonomous systems**: you start from a client's problem and descend,
pass by pass, until working code merges itself because an eval said so.

It runs as **seven passes, in a fixed order**. Each pass does three things:

- **lowers the altitude** — from problem, to understanding, to plans, to tasks, to code;
- **binds an engine** — the right tool for that altitude (Chat, Code, Codex, a skill, an executor);
- **ends at a gate** — a checkpoint you confirm before you descend.

The one rule that holds the whole thing together:

> **Converged = an eval passed, not "it feels done."**

A pass is finished when its gate holds. The build is finished when every task's
eval is green. There is no "looks right" in Converge — there is "the eval passed."

> Visual companions: **`docs/cvg-aut-systems-spine.pdf`** — the deck that draws the
> spine, the altitude drop, and the gates; read this runbook with it open. And
> **`docs/brd-analytical-backbone.pdf`** (source: `presentation/brd-analytical-backbone-deck.html`)
> — the client's brief, the Pass 1 input you attach in CoWork.

---

## The spine

```text
Intent → Structure → Decomposition → Consensus → Tasking → Harness → Execution
```

```text
ALTITUDE
  high   1 Intent        problem → verifiable spec
   │     2 Structure     spec ↔ real repo (understanding)
   │     3 Decomposition understanding → two plans
   │     4 Consensus     plans → plans, adversarially sharpened
   │     5 Tasking       plans → atomic, eval-bearing tasks
   │     6 Harness       tasks → the .claude/ control layer
  low    7 Execution     tasks → merged code (eval = merge)
```

Each row is one pass. You never skip a row, and you never climb back up without
a reason — a failed gate sends you back one step, not to the top.

---

## The seven passes at a glance

| Pass | Engine | In → Out | Gate | Prompt |
|------|--------|----------|------|--------|
| 1 · Intent | Claude CoWork (a project) | `brd-analytical-backbone.pdf` → `tech-spec-analytical-engine.pdf` | Spec answers the brief; every requirement verifiable & KPI-tied; **no premature tech** | [`p1-intent.md`](p1-intent.md) |
| 2 · Structure | Claude Code (repo open) | tech-spec + `src/` → *understanding (no file)* | You can explain the system vs. the real repo; brownfield runs | [`p2-structure.md`](p2-structure.md) |
| 3 · Decomposition | Claude Code (Auto, **same session**) | understanding → `sketch/duckdb-dbt-med-arch.plan` + `sketch/fast-api-mcp.plan` | Two plans split at the real seam; deps + build order; serving names its gold interface | [`p3-decomposition.md`](p3-decomposition.md) |
| 4 · Consensus | Codex (adversary) ↔ Claude | the two plans → the two plans, **sharpened in place** | No objection survives; **the fork is decided — Fork B, task-driven** | [`p4-consensus.md`](p4-consensus.md) |
| 5 · Tasking | `task-spec` skill | the two plans → `tasks/*` | Every task atomic, **tech-described (not agent-named)**, binds a runnable eval | [`p5-tasking.md`](p5-tasking.md) |
| 6 · Harness | `agents-kbs-tech-stack` skill | `tasks/*` → `.claude/` (+ emitted mirrors) | Control layer stands — each tech a task needs has an agent + grounded KB | [`p6-harness.md`](p6-harness.md) |
| 7 · Execution | Claude Code Workflows / AgentSpec / Kimi Crank | `tasks/*` + `.claude/` → merged code | **Eval passes = merged** — the loop closer | [`p7-execution.md`](p7-execution.md) |

---

## The artifacts, in the order they appear

The trail Converge leaves behind — one direction, each pass feeding the next:

```text
docs/brd-analytical-backbone.pdf        GIVEN by the client (the problem — the input)
        │ Pass 1
docs/tech-spec-analytical-engine.pdf    OUR deliverable (the solution shape — verifiable, no tech)
        │ Pass 2 — no file; understanding held in the session
        │ Pass 3
sketch/duckdb-dbt-med-arch.plan         the medallion plan (dbt bronze→silver→gold over raw.*)
sketch/fast-api-mcp.plan                the serving plan (FastAPI/MCP over the gold tables)
        │ Pass 4 — sharpened in place; the diff IS the record of consensus
        │ Pass 5
tasks/*                                 one file per atomic unit, each with a runnable eval
        │ Pass 6
.claude/                                agents + KBs + rules + CLAUDE.md (+ AGENTS.md / Cursor / Copilot mirrors)
        │ Pass 7
merged code                             the dbt medallion + the FastAPI/MCP layer — every piece earned merge by an eval
```

The BRD is the only artifact you do **not** produce — the client hands it to you.
Everything below it is yours.

---

## Reproduce it live

An ordered walkthrough on **this** repo — a Postgres → DuckDB analytics base. The
brownfield (`src/`: Postgres source, seeder, 14-mode generator, the `raw.*`
landing) already runs; Converge builds the **dbt medallion** and the **FastAPI/MCP**
serving layer on top. Run each pass, confirm its gate, then descend.

### Pass 1 · Intent — Claude CoWork

- **Engine:** Claude CoWork (a project) — conversational, no repo, no code.
- **Do:** open a CoWork project, attach `docs/brd-analytical-backbone.pdf`, open
  [`p1-intent.md`](p1-intent.md), and run its three steps (understand →
  interrogate → crystallize).
- **Out:** `docs/tech-spec-analytical-engine.pdf`.
- **Gate before moving on:** the spec answers the brief — every client pain maps
  to a **verifiable**, KPI-tied requirement; scope is explicit; **no premature
  technology** (the stack belongs to Pass 3).

### Pass 2 · Structure — Claude Code

- **Engine:** Claude Code, repo open. **Open this session and keep it open into Pass 3.**
- **Do:** open [`p2-structure.md`](p2-structure.md). Prove the brownfield works before you trust the spec:
  ```bash
  make up && make seed && make land
  ```
  Expect Postgres `customers=500, products=200, orders=5000, payments=5000` and
  DuckDB `raw.*` with exact row parity. Confirm the warehouse holds **`raw.*` only** —
  no transform or serving layer exists yet.
- **Out:** none — the loaded understanding **is** the handoff.
- **Gate:** you can explain the full system (given vs. to-build), the brownfield
  reconciles with row parity, and the spec is consistent with the real `src/`.

### Pass 3 · Decomposition — Claude Code (Auto, same session)

- **Engine:** Claude Code in Auto Mode — the **same session as Pass 2**, so the understanding carries over.
- **Do:** open [`p3-decomposition.md`](p3-decomposition.md). Find the seam (the
  brownfield ends at `raw.*`; above it splits into *shaping* vs. *exposing*), then
  write the two plans.
- **Out:** `sketch/duckdb-dbt-med-arch.plan` and `sketch/fast-api-mcp.plan`.
- **Gate:** two plans split at the real seam (transformation vs. serving), each
  with features, deps, and build order; the serving plan names the **gold-table
  interface** it consumes; plan altitude held (no tasks, no SQL).

### Pass 4 · Consensus — Codex ↔ Claude

- **Engine:** Codex as the adversary (a *different* model — Claude won't refute itself hard enough), Claude defends and revises.
- **Do:** open [`p4-consensus.md`](p4-consensus.md). Run Codex (e.g. `/codex` or
  the codex review skill) to refute the two plans, grill them against the
  tech-spec for drift, then sharpen back in Claude Code.
- **Out:** the **same two plans, sharpened in place** + a short open-questions list.
- **Gate:** every objection is **fixed** in a plan or **accepted** with an owner;
  the medallion→serving interface survived; **the fork is named — Fork B,
  task-driven** (recorded at the top of both plans).

### Pass 5 · Tasking — the `task-spec` skill

- **Engine:** the `task-spec` skill — self-contained and engine-agnostic (it carries its own task-architect; it authors tasks **without** the harness).
- **Do:** open [`p5-tasking.md`](p5-tasking.md). Cut the two plans into atomic
  units in build order (bronze → silver → gold → endpoints → MCP tools), describe
  each by **tech and artifact** (never by agent), and bind each a runnable eval.
- **Out:** `tasks/*` — one file per atomic unit.
- **Gate:** every task is atomic, tech-described, self-contained (readable without
  `.claude/`), and **binds a runnable eval** tied to the real flow
  (`make seed → make land → dbt run → query gold`).

### Pass 6 · Harness — the `agents-kbs-tech-stack` skill

- **Engine:** the `agents-kbs-tech-stack` skill — scaffolds the control layer fitted to the tasks.
- **Do:** open [`p6-harness.md`](p6-harness.md). Inventory the techs the tasks
  invoke (here: dbt, DuckDB, FastAPI/MCP), scaffold an agent + grounded KB per
  tech plus the universal closers, then emit the cross-tool mirrors.
- **Out:** `.claude/` (agents + KBs + rules + `CLAUDE.md`) and the emitted
  `AGENTS.md` / Cursor / Copilot mirrors.
- **Gate:** every tech a task needs has an agent and a cited KB; `CLAUDE.md` + rules
  encode the `raw.*→gold` seam, the one-way Postgres→DuckDB dependency, and
  "eval passes = done"; mirrors are emitted from `.claude/`, never hand-edited;
  **nothing scaffolded that no task asked for** (no Dagster, no CrewAI).

### Pass 7 · Execution — Claude Code Workflows / AgentSpec / Kimi Crank

- **Engine:** the right executor per task — Kimi Crank for mechanical models,
  Claude (Code Workflows / AgentSpec) for judgment work, Codex to review the diff.
- **Do:** open [`p7-execution.md`](p7-execution.md). Walk `tasks/` in build order,
  dispatch each to its engine with the harness loaded, then run **its** eval. The
  pipeline every eval can assume is real:
  ```bash
  make seed && make land   # → dbt run → query gold
  ```
- **Out:** merged code — the dbt medallion (bronze→silver→gold over `raw.*`) and
  the FastAPI/MCP layer over gold.
- **Gate:** **the eval passes = merged.** A task whose eval can't go green is
  blocked, not merged. When the set is green, run the end-to-end once more to
  confirm the spine composes.

---

## Why this order

The sequence is not arbitrary — four principles fix it in place:

- **Consultant framing — the BRD is given, the spec is produced.** The client
  owns the problem and hands you `brd-analytical-backbone.pdf` (the *what* and
  *why*). Pass 1 comprehends it and produces `tech-spec-analytical-engine.pdf`
  (the *how*). Brief = the problem; spec = the solution. **No tech lives in the
  brief**, and Pass 1 keeps the spec above the stack too.

- **Pass 2 → Pass 3 is one session — no file handoff.** Structure produces no
  artifact; its output is the understanding loaded in Claude Code's context.
  Decomposition runs in the **same, never-closed** session, because that
  understanding *is* the handoff. Close the session and you lose it.

- **Tasking (5) before Harness (6) — on purpose.** `task-spec` is self-contained,
  so it authors the tasks before any `.claude/` control layer exists, describing
  the **work** (tech + eval), not the harness agents. Pass 6 then reads what the
  tasks need and scaffolds exactly that. A forward dependency, no circularity — if
  the harness came first you'd be guessing the techs.

- **The close-the-loop question is "did the eval pass?"** — never "does it feel
  done?". Every task carries a runnable eval; a green eval is the merge signal.
  That single question is what keeps the loop honest, especially once it runs
  unattended.

---

## Notes

- **The prompt cards are the script; this README is the map.** Each `pN-*.md` is a
  copy-paste card (header lines, a teaching note, three steps A → B → C, a gate
  checklist, practical notes). Run them in order; confirm each gate before the next.
- **Gates are non-negotiable; lengths are not.** The prompts are short because
  *you're watching*. To hand a pass to an unwatched engine, spell out the output
  structure — but the gate constraints (verifiable, eval-bearing, no premature
  tech, eval = merge) never drop.
- **Scope for this repo:** Postgres → DuckDB → **dbt medallion** → **FastAPI/MCP**.
  No Dagster, no CrewAI/Sentinel — they are explicitly out of scope here, and the
  harness in Pass 6 must not scaffold them.
- **One direction only.** The brownfield is the floor: Postgres is the source,
  DuckDB the analytical store, `transition` the one `ATTACH` read-only bridge.
  Everything Converge builds reads from `raw.*` upward and never writes back down.
