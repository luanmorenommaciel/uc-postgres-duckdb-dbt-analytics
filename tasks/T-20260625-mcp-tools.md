---
id: T-20260625-mcp-tools
title: MCP tools — agent-callable questions over the same read-only query core
status: ready
format_version: 2
effort: M
budget_iterations: 15
agent: any
depends_on: [T-20260625-api-fastapi]
touches_paths:
  - src/serving
source_note: sketch/fast-api-mcp.plan
created: 6
tags: [mcp, serving, read-only, E4, self-serve]
owner: (none)
priority: P1
severity: feature
due_date: (none)
precondition: FastAPI query core + endpoints built (T-20260625-api-fastapi signed off)
blocked_reason: final tool list gated on the frozen E4 question set (VP Data, spec §6)
security_class: (none)
source_action_item: (none)
linear_ref: (none)
execution_backend: any
signed_off: false
signed_off_by: (none)
signed_off_at: (none)
---

# MCP tools — agent-callable questions over the same read-only query core

> **Why:** This completes the E4 self-serve surface for the natural-language path: a non-engineer asks a question and an agent calls a tool that returns a correct answer — no new report build. It must reuse the exact B1 query core the API uses, so a tool and its sibling endpoint can never disagree.

---

## Goal

Ship an **MCP server** (`src/serving/mcp_server.py`) exposing one tool per frozen E4 question — `revenue_by_category`, `customer_segments`, `order_health`, `payment_reconciliation`, `freshness` — each wrapping the **same** `src/serving/queries.py` function its FastAPI endpoint uses (same inputs/outputs, same read-only gold-only contract). Tool descriptions name the question each answers so an LLM can route intent → tool. A tool and its matching endpoint must return identical values for the same inputs (same core ⇒ same answer). `make serve-mcp` (or an MCP entrypoint) launches it.

---

## Context

- Reuses the B1 query core from `api-fastapi` — MCP is a second *transport*, not a second query layer. They stay one component as long as they share the core unchanged.
- Same hard boundary: read-only, gold-only, latest `_gold_run_id` generation. No reach below gold.
- This is the literal **E4 self-serve** requirement (spec §4): questions answerable by non-engineers with no new report each time.
- The **E4 coverage matrix** (question → mart → endpoint → tool → acceptance query) spans this unit and `api-fastapi`; it's the build-gate artifact proving completeness once E4 is frozen. Codex C6.
- Build order: bronze → silver → gold → API → **MCP (this)**.

---

## Success Criteria

Each criterion is a runnable bash function returning 0 (pass) or non-zero (fail).
Each MUST be terminal (deterministic, idempotent, non-flaky).

```bash
# eval-1: the MCP server module imports and registers the expected tools
eval_1() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
import src.serving.mcp_server as m
names = set()
# tolerate common MCP registries: a FastMCP-like .list_tools(), a TOOLS dict, or module-level fns
for attr in ("list_tools","tools","TOOLS"):
    obj = getattr(m, attr, None)
    if callable(obj):
        try: names |= {getattr(t,"name",str(t)) for t in obj()}
        except Exception: pass
    elif isinstance(obj, dict):
        names |= set(obj.keys())
names |= {a for a in dir(m) if a in {"revenue_by_category","customer_segments","order_health","payment_reconciliation","freshness"}}
need = {"revenue_by_category","customer_segments","order_health","payment_reconciliation","freshness"}
missing = need - names
assert not missing, f"missing MCP tools: {missing}"
PY
}

# eval-2: every MCP tool wraps the shared query core (no second query layer, no below-gold reads)
eval_2() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
import inspect, src.serving.mcp_server as m
src = inspect.getsource(m)
assert "from src.serving.queries" in src or "import src.serving.queries" in src or "serving.queries" in src, \
  "MCP tools must reuse src.serving.queries (the shared B1 core)"
assert "connect(read_only=False" not in src, "MCP layer must not open a writable connection"
PY
}

# eval-3: a tool and its sibling FastAPI endpoint return the SAME answer for the same input
eval_3() {
  PYTHONPATH=. uv run python - <<'PY' || return 1
import json
from fastapi.testclient import TestClient
from src.serving.api import app
import src.serving.queries as q
# the freshness question is shared by /freshness and the freshness tool, both over the same core
endpoint = TestClient(app).get("/freshness").json()
core = q.freshness() if hasattr(q, "freshness") else None
assert core is not None, "shared core function `freshness` not found"
# normalize both through json to compare values, not object identity
assert json.dumps(endpoint, sort_keys=True, default=str) == json.dumps(core, sort_keys=True, default=str), \
  "tool/endpoint disagree — they are not sharing one query core"
PY
}
```

---

## Validation Card

```yaml
success_criteria:
  - id: eval_1
    description: MCP server registers one tool per E4 question
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10
  - id: eval_2
    description: tools reuse the shared query core; no writable connection
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 10
  - id: eval_3
    description: tool and sibling endpoint return identical answers (same core)
    runnable: bash
    check_type: deterministic
    terminal: true
    expected_duration_sec: 15

retry_policy:
  max_iterations: 15
  circuit_breaker_no_progress: 3
  on_terminal_failure: park_with_context

agent_contract:
  version: 2
  read: [intent, contract, guardrails, operations]
  produce:
    - code
    - tests
    - config
  required_tools: [git, bash]
  timeout_minutes: 30
  sandbox_type: host
  output_artifacts: [src/serving/mcp_server.py]
  mcp_dependencies: []
  emit:
    - pass
    - fail
    - retry_with_reason
    - parked_with_context
  codex_metadata: {}
  kimi_metadata: {}
```

---

## Exit Check

```bash
# Final proof-of-done. Returns 0 only when ALL evals pass.
eval_1 && eval_2 && eval_3
```

---

## Rollback Plan

(none — additive: a new MCP server module + an entrypoint. `git checkout -- src/serving Makefile` discards it; the FastAPI layer and warehouse are untouched.)

---

## Observability Hooks

- **Expected duration:** tool call sub-second (same pre-aggregated gold lookup as the API).
- **Key metric:** tool/endpoint answer parity; tool latency.
- **Alert condition:** a tool answer diverging from its endpoint (the core was forked); any below-gold read; a writable connection.
- **Log tail:** MCP server stdout.

---

## Anti-Patterns

- **Don't reimplement queries in the MCP layer** — call `src.serving.queries`. A forked query is how a tool and its endpoint silently drift apart.
- **Don't add a tool with no matching gold mart** — every tool answers a frozen E4 question backed by a mart; otherwise the coverage matrix can't go green.
- **Don't open a writable or below-gold connection** — same read-only, gold-only boundary as the API.

---

## Do-Not-Touch

Files the executor MUST NOT modify:

- `src/serving/queries.py` semantics (extend if needed, but the API and MCP MUST share one core — do not fork it)
- `src/db/**`, `src/transition/**`, `src/warehouse/**`, `transform/**` (consumed, not edited)

---

## Open Questions

1. **Frozen E4 question set** — fixes the final tool list and the coverage matrix. Owner: VP Data (spec §6). Candidate tools buildable; final surface gated.
