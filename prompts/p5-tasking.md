# Converge · Pass 5 — Tasking

**Engine:** the `task-spec` skill — self-contained and engine-agnostic (it carries its own task-architect and scripts; it authors tasks without the harness).
**Inputs:** `sketch/duckdb-dbt-med-arch.plan` · `sketch/fast-api-mcp.plan` (sharpened in Pass 4).
**Output:** `tasks/*` — one file per atomic unit, each carrying a **runnable eval**.
**Gate:** every task is atomic, described by TECH (not by agent), and binds an eval that actually runs.

Three steps: **cut atomic units → describe by tech → bind a runnable eval.**

> Teaching note: Tasking comes BEFORE Harness on purpose. A task is the requirement; the harness is fitted to it. `task-spec` is self-contained, so it authors the tasks without any `.claude/` control layer existing yet — and it describes the *work* (the tech and the eval), never the agent that will do it. That forward dependency is what lets Pass 6 scaffold exactly what the tasks need, with no circularity.

---

## Step 1 · Cut atomic units

```text
Using the two sharpened plans, cut them into atomic tasks — the smallest units
that can be built and verified on their own. Walk the build order: bronze models,
then silver, then gold marts, then each FastAPI endpoint, then each MCP tool. One
task = one shippable thing with one clear done-condition. If a "task" needs two
unrelated things proven, split it. Write one file per task under tasks/.
```

## Step 2 · Describe by tech, not by agent

```text
For each task, describe the WORK in terms of the technology and the artifact —
"a dbt silver model that conforms orders and passes not_null/unique tests on the
grain", "a FastAPI GET endpoint over gold.<mart> returning the top-N by revenue".
Name the tech (dbt, DuckDB SQL, FastAPI, MCP), the inputs it reads, and the
artifact it produces. Do NOT name an agent or assign a model — the task states
the requirement; who builds it is decided later. Keep each task self-contained:
it must be readable without the harness existing.
```

## Step 3 · Bind a runnable eval

```text
Give every task a RUNNABLE eval — a command whose pass/fail is unambiguous, tied
to the brownfield's make flow where possible. Examples by kind:

- dbt model: `dbt build --select <model>` is green AND its schema tests pass.
- gold mart: a DuckDB query against gold returns the expected shape/row count
  (e.g. SELECT over gold.<mart> returns N rows / non-null revenue).
- FastAPI endpoint: a request to the route returns 200 with the contracted JSON.
- MCP tool: invoking the tool responds with the expected payload from gold.

The whole pipeline an eval can assume is real: `make seed → make land → dbt run →
query gold`. State the exact command and the expected result in the task. "Done"
means the eval passes — never "looks done".
```

---

## Gate — confirm before leaving Pass 5

- [ ] Every plan item is cut into atomic tasks under `tasks/`.
- [ ] Each task is described by TECH and artifact — no agent named, no model assigned.
- [ ] Each task is self-contained — readable without the `.claude/` harness existing.
- [ ] **Every task binds a runnable eval** with an exact command and expected result.
- [ ] Evals tie to the real flow (`make seed → make land → dbt run → query gold`) where applicable.
- [ ] Build order is preserved across the task set (bronze → silver → gold → API → MCP).

When these hold, the tasks are the requirements **Pass 6 — Harness** is fitted to.

---

### Notes

- **`task-spec` is self-contained on purpose.** It brings its own task-architect and scripts, so it doesn't need the harness to author tasks. That's why Tasking precedes Harness — the tasks are the spec the harness answers to.
- **Tech-described, not agent-named.** A task says "a dbt silver model with these tests", not "the dbt-developer builds this". Naming the agent here would invert the dependency — Pass 6 reads the tasks' tech needs and scaffolds exactly those agents/KBs.
- **The eval is the contract.** A task without a runnable eval can't converge — there's nothing to close the loop against. If you can't write the eval, the task isn't atomic enough yet.
- **Unattended later?** A precisely-specified task with a runnable eval is exactly what an unwatched engine can execute and self-check. The eval is what makes hands-off execution safe.
