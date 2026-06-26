# Pattern · Analytical Tool Server

> **Solves:** Exposing a fixed set of analytical questions as agent-callable MCP
> tools that reuse the SAME read-only query core the HTTP API uses — so a tool and
> its sibling endpoint can never give different answers.
> **Limit:** ~200 lines. One reusable pattern, production-grade.

## Source of truth

- MCP spec: <https://modelcontextprotocol.io/> · Tools: <https://modelcontextprotocol.io/specification/2025-06-18/server/tools>
- Python SDK / FastMCP: <https://github.com/modelcontextprotocol/python-sdk>
- This repo's plan/task: `sketch/fast-api-mcp.plan`, `tasks/T-20260625-mcp-tools.md`

## Problem

Component B (Serve) answers a frozen set of E4 questions —
`revenue_by_category`, `customer_segments`, `order_health`,
`payment_reconciliation`, `freshness` — over two transports. The FastAPI endpoints
serve dashboards and programmatic callers; the **MCP tools serve agents** so a
non-engineer can ask in natural language and get a correct answer with **no new
report build** (the literal E4 self-serve requirement). The trap: building the MCP
tools as a second query layer. The moment a tool reimplements the SQL its endpoint
runs, the two **silently drift** — same question, two answers, and the gold/serving
boundary (read-only, gold-only, latest `_gold_run_id`) gets re-stated wrong in a
second place. The pattern is: **one tool per question, each tool is a thin wrapper
that calls the one shared query core** (`src/serving/queries.py`).

## Pattern

`src/serving/mcp_server.py` — a FastMCP server whose tools delegate, never query.

```python
"""MCP transport for Component B (Serve).

One agent-callable tool per frozen E4 question. Every tool is a THIN wrapper over
src.serving.queries — the SAME core the FastAPI endpoints use. A tool and its
sibling endpoint MUST return identical values: same core => same answer.

Hard boundary (inherited from the query core, not re-stated here):
read-only, gold-only, latest published _gold_run_id generation. No writable
connection is ever opened in this module.
"""
from __future__ import annotations

from mcp.server.fastmcp import FastMCP

# The ONE query layer. Never reimplement a query below — always delegate.
from src.serving import queries

mcp = FastMCP("uc-analytics")


@mcp.tool()
def revenue_by_category(start: str, end: str) -> list[dict]:
    """Daily revenue and order count per product category over a date range.

    Answers: 'How much revenue did each category make per day?'
    Args: start/end are ISO dates (YYYY-MM-DD), inclusive.
    """
    return queries.revenue_by_category(start=start, end=end)


@mcp.tool()
def customer_segments(start: str, end: str) -> list[dict]:
    """Customer segments with lifetime value and order count over a date range.

    Answers: 'Which customer segments are most valuable?'
    """
    return queries.customer_segments(start=start, end=end)


@mcp.tool()
def order_health(start: str, end: str) -> list[dict]:
    """Per-day order status-rate health and defect count over a date range.

    Answers: 'Are orders flowing through to fulfilment, or stalling?'
    """
    return queries.order_health(start=start, end=end)


@mcp.tool()
def payment_reconciliation(start: str, end: str) -> list[dict]:
    """Per-day paid vs ordered totals, refund rate, and orphan count.

    Answers: 'Do payments reconcile against orders?'
    """
    return queries.payment_reconciliation(start=start, end=end)


@mcp.tool()
def freshness() -> dict:
    """Latest warehouse freshness: max ingested/event timestamps and the
    event-to-reportable lag (the E3 observable instrument).

    Answers: 'How fresh is the data I'm looking at?'
    """
    return queries.freshness()


if __name__ == "__main__":
    # stdio is the default transport — hosts like Claude Desktop launch this
    # module as a child process and speak JSON-RPC over its stdin/stdout.
    mcp.run()
```

The query core it delegates to opens only a read-only handle (already shipped in
`src/warehouse/connection.py`):

```python
# inside src/serving/queries.py — the ONE place gold is read
from src.warehouse.connection import connect_read_only  # access_mode=READ_ONLY

def freshness() -> dict:
    with connect_read_only() as conn:   # never connect(read_only=False)
        # SELECT ... FROM gold_freshness  (latest _gold_run_id only; no read below gold)
        ...
```

<!-- TODO: src/serving/queries.py and src/serving/mcp_server.py are NOT built yet
     (T-20260625-mcp-tools is `ready`, depends on T-20260625-api-fastapi). The code
     above is the target shape this pattern prescribes; bind the exact function
     signatures to queries.py once the FastAPI query core is signed off. -->

## Why this shape

- **One core, two transports.** The endpoint and the tool both call
  `queries.<question>()`. They differ only in protocol framing (HTTP vs JSON-RPC),
  never in SQL. This is what makes "same core ⇒ same answer" true by construction
  rather than by discipline — and keeps B2/B3 a single component (`fast-api-mcp.plan`).
- **Tools, not resources.** Each question is a parameterized, model-invoked **action**
  over gold (date ranges, filters), not addressable static data — so it's a `@mcp.tool()`.
  See `concepts/tools-vs-resources.md`.
- **Boundary stated once.** Read-only / gold-only / latest-`_gold_run_id` lives in the
  query core. The MCP module inherits it by delegating; it never opens its own
  connection, so it can't reintroduce a writable or below-gold read.
- **Descriptions are routing.** Each docstring names the question it answers so an
  LLM can route NL intent → the right tool (the E4 self-serve mechanism).

## Anti-patterns

- **Reimplementing the query in the tool.** A forked query is how a tool and its
  endpoint silently disagree. Call `queries.<fn>`; never write SQL in `mcp_server.py`.
- **Opening a connection in the MCP module.** `connect(read_only=False)` — or any
  direct `duckdb.connect` here — breaks the read-only boundary. Delegation only.
- **A tool with no matching gold mart.** Every tool answers a frozen E4 question
  backed by a mart; a tool without one can't go green on the coverage matrix. Need a
  new column? That's a new gold mart request to Component A, never a deeper read here.
- **Reaching below gold** (`silver.*`, `bronze.*`, `raw.*`, Postgres) — forbidden;
  the query core reads `gold.*` only.

## Verify

- **eval-1 (registration):** importing `src.serving.mcp_server` exposes tools named
  `revenue_by_category`, `customer_segments`, `order_health`,
  `payment_reconciliation`, `freshness`.
- **eval-2 (shared core, no writes):** the module source imports
  `src.serving.queries` and contains **no** `connect(read_only=False`.
- **eval-3 (parity):** a tool and its sibling endpoint return identical values for
  the same input — e.g. `TestClient(app).get("/freshness").json()` equals
  `queries.freshness()` once normalized through JSON. This is the proof they share one core.

See `tasks/T-20260625-mcp-tools.md` for the runnable eval bash.

## See also

- `quick-reference.md` — this tech's index
- `reference/server-sdk-api.md` — FastMCP define/register/run signatures
- `concepts/tools-vs-resources.md` — why these are tools, not resources
- `patterns/nl-to-sql-tool.md` — fixed analytical tools vs free-form SQL
