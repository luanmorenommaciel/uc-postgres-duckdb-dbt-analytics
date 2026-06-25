# Converge · Pass 4 — Consensus

**Engine:** Codex (the adversary) + Claude (defends & revises) + the docs as ground truth. Disagreement needs a *different* model — Claude won't refute itself hard enough.
**Inputs:** `sketch/duckdb-dbt-med-arch.plan` · `sketch/fast-api-mcp.plan` · `docs/tech-spec-analytical-engine.pdf`.
**Output:** the **same two plans, sharpened in place**, plus a short open-questions list, AND the named fork decision.
**Gate:** no open objection remains — every attack is fixed in the plan or accepted as an owned risk — and the fork is decided: **Fork B, task-driven**.

Three steps: **attack → grill against the spec → sharpen.**

> Teaching note: plan → adversarially sharpen → build. The cheapest place to kill a wrong idea is the plan, before any model or endpoint exists. We don't ask Claude "is this good?" — it agrees with itself. We bring a *different engine* (Codex) to refute. That cross-model disagreement is the whole point of this pass.

---

## Step 1 · Attack — let Codex refute the plans

Run via the Codex plugin (e.g. `/codex` or the codex review skill). Prompt:

```text
You are a skeptical principal engineer reviewing two implementation plans you did
NOT write. Your job is to REFUTE them, not bless them.

Read sketch/duckdb-dbt-med-arch.plan and sketch/fast-api-mcp.plan. Find what will
bite us at build time:

- Where is a plan vague, hand-wavy, or assuming something unproven about the
  brownfield (the raw.* contract, the three stamp columns, DuckDB single-writer)?
- Where will the build order break — a layer that needs something not yet built
  (gold before silver, an endpoint before the mart it reads)?
- Is the medallion→serving interface actually complete, or does an endpoint/MCP
  tool need a gold column the medallion plan never produces?
- Any mismatch of KIND — e.g. a freshness expectation a full-refresh dbt run
  can't meet, or DuckDB concurrency the API assumes it has?

Give me the 5-7 highest-leverage objections, ranked by how much damage each would
cause if we built as-is. Be specific and cite the plan section. Default to
refuted — if something is merely plausible, say why it might be wrong.
```

**Why:** Codex is a different model with no ego in Claude's plans. "Default to refuted" forces attack over rubber-stamp. Ranking by damage tells you what to fix first.

## Step 2 · Grill against the spec — ground-truth check

```text
Now check both plans against the tech-spec. For each plan, find where it
CONTRADICTS or DRIFTS from the spec:

- Does it claim to satisfy a requirement it doesn't actually cover?
- Does it contradict the spec's scope (e.g. building something marked out, or a
  gold metric the spec never asked for)?
- Does any number — freshness target, latency budget, success metric — disagree
  with the spec?

List each drift as: plan section ↔ spec section ↔ the conflict. No hand-waving —
cite both sides.
```

**Why:** the plans answer to the spec, not to Claude's memory of it. This catches the silent drift where a plan *sounds* right but quietly contradicts the agreed source of truth.

## Step 3 · Sharpen — resolve every objection, then decide the fork

Back in Claude Code, with Codex's objections in hand:

```text
Here are the objections from the adversarial review [paste them]. For EACH one,
do exactly one of:

1. FIX — revise the relevant plan (duckdb-dbt-med-arch.plan or fast-api-mcp.plan)
   in place to resolve it, or
2. ACCEPT — record it as a known risk with an owner and a reason we proceed.

Nothing may be silently dropped. Then make THE FORK decision explicit at the top
of both plans: this project is FORK B — task-driven. We do NOT hand the whole
spec to one autonomous agent; we cut the plans into atomic tasks, each with its
own eval, and dispatch per task. State that, and why it fits this build (a
deterministic medallion + a thin serving layer, each step independently
verifiable). Finish with a short open-questions list: each remaining item, its
owner, and whether it blocks the build.
```

**Why:** the gate made operational. Every attack lands somewhere — fixed or owned — and the fork is named on the record, because Pass 5 (tasking) only makes sense once we've committed to the task-driven path.

---

## Gate — confirm before leaving Pass 4

- [ ] Codex (a different engine) attacked the plans — not Claude self-reviewing.
- [ ] Plans were grilled against the tech-spec for drift.
- [ ] Every objection is FIXED in a plan or ACCEPTED with an owner.
- [ ] The medallion→serving (gold-table) interface survived scrutiny, or was corrected.
- [ ] **The fork is named: Fork B, task-driven** — recorded in both plans.
- [ ] Open-questions list exists; blockers are flagged.

When these hold, the sharpened plans feed **Pass 5 — Tasking**, where each is cut into atomic, eval-bearing units.

---

### Notes

- **Codex is the engine, not a courtesy.** Claude reviewing its own plans gives agreement, not consensus. The cross-model refutation is the value. (Fallback if Codex is down: a fresh Claude session with no memory of writing the plans — weaker, but better than self-review in the same context.)
- **Known live ammunition** for the adversary here: the **freshness gap** (full-refresh dbt vs. any near-real-time intent in the spec), **DuckDB single-writer** (can the API read while a `dbt run` writes? the warehouse contract says readers may run concurrently with one writer — confirm the plan relies only on that), and **interface completeness** (does every endpoint/tool read a gold column the medallion actually emits?).
- **The fork is the decision of this pass, not a footnote.** Fork A would hand the spec to one agent and let it run; Fork B cuts tasks first. We pick B because every medallion layer and every endpoint has a cheap, runnable eval — so task-by-task convergence beats one big autonomous run.
- **Sharpen in place.** Pass 4 creates no new files — it hardens the two plans. The diff on those files IS the record of what consensus changed.
