# Converge · Pass 7 — Execution

**Engine:** Claude Code Workflows / AgentSpec / Kimi Crank — the right engine per task.
**Inputs:** `tasks/*` (each with its runnable eval) · the grounded `.claude/` harness · the repo.
**Output:** merged code — the dbt medallion (bronze→silver→gold over `raw.*`) and the FastAPI/MCP layer over gold.
**Gate:** the eval passes = merged. The loop closer — converged means an eval passed, not "feels done".

Three steps: **dispatch → run each task's eval → loop until green, then merge.**

> Teaching note: this is where the spine lands as code. Every prior pass existed so this one is mechanical: a task with a runnable eval and a grounded harness can be dispatched to the right engine and self-checked. We don't ask "does it feel done?" — we ask "did the eval pass?". That question is the loop closer.

---

## Step 1 · Dispatch — right engine per task

```text
Walk tasks/ in build order. For each task, pick the engine that fits the work:

- Kimi Crank — mechanical, high-volume models with a tight spec (the repetitive
  dbt bronze/silver models; staging over raw.*). Crank them.
- Claude (Code Workflows / AgentSpec) — judgment work: the gold marts, the
  business rules, the FastAPI/MCP wiring where shape and contract matter.
- Codex — review the diff before merge (a second engine on the output, same way
  it adversarially reviewed the plans in Pass 4).

Dispatch each task to its engine with the harness loaded, so the tech agent
grounds in its KB as it builds.
```

## Step 2 · Run each task's eval

```text
For each built task, run ITS eval — the exact command the task carries. The
pipeline every eval can assume is real:

  make seed → make land → dbt run → query gold

Examples: a dbt model task passes when `dbt build --select <model>` is green and
its schema tests pass; a gold mart passes when the DuckDB query returns the
contracted shape; a FastAPI endpoint passes on a 200 with the contracted JSON; an
MCP tool passes when invoking it returns the expected gold-backed payload. Run the
eval, don't eyeball the code.
```

## Step 3 · Loop until green, then merge

```text
If the eval fails, feed the failure back to the building engine, fix, and re-run
— loop until the eval is green. Only a green eval merges. A task whose eval can't
go green is blocked, not merged — surface it, don't paper over it. When the full
set is green, run the end-to-end once more (make seed → make land → dbt run →
query gold, plus hit the API/MCP) to confirm the whole spine holds, then merge.
```

---

## Gate — confirm before leaving Pass 7

- [ ] Each task was dispatched to the engine that fits it (Kimi cranks, Claude judges, Codex reviews).
- [ ] Every merged task's eval was RUN and passed — not eyeballed.
- [ ] The end-to-end runs green: `make seed → make land → dbt run → query gold`, plus the API/MCP responds.
- [ ] Failing-eval tasks are surfaced as blocked, never silently merged.
- [ ] Only green-eval code is in the merge.

When these hold, the build is converged — the medallion and serving layer stand on the brownfield, and every piece earned its merge by passing an eval.

---

### Notes

- **Right engine per task is the point of Fork B.** Because Pass 5 cut atomic, eval-bearing tasks, you can route the mechanical ones to Kimi and reserve Claude's judgment for the marts and the API — and have Codex review the diff. One big autonomous run can't do that triage.
- **The eval is the merge gate, full stop.** "Converged = an eval passed" is the whole methodology in one line. No eval, no merge — that's what keeps an unattended loop honest.
- **End-to-end is the final proof.** Individual evals prove each unit; the `make seed → make land → dbt run → query gold` run proves they compose. Run it before you call it done.
- **Unattended later?** This is the pass that automates first — a green eval is a machine-checkable merge signal. Once the loop is "build → run eval → merge if green", the human moves from doing the work to gating the evals.
