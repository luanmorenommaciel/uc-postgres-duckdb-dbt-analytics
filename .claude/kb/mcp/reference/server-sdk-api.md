# Reference · MCP Server SDK API (Python / FastMCP)

> **Scope:** The Python MCP server API this project ships on — how to define a
> server, register a tool, and run it over stdio for hosts like Claude Desktop.
> FastMCP is the high-level server API bundled inside the official `mcp` package.
> **No line limit.** This is lookup material — completeness over brevity.

## Source of truth

Every claim below traces to one of these. Update the date when you refresh.

- MCP spec (home): <https://modelcontextprotocol.io/>
- MCP specification: <https://modelcontextprotocol.io/specification>
- Tools concept (spec): <https://modelcontextprotocol.io/specification/2025-06-18/server/tools>
- Python SDK (FastMCP lives here): <https://github.com/modelcontextprotocol/python-sdk>
- Verified against: python-sdk `README.md` / `docs/` and the 2025-06-18 spec, checked 2026-06-25.

## Install

The high-level server API ships inside the single `mcp` package.

| Tool | Command |
|------|---------|
| pip | `pip install mcp` |
| uv  | `uv add mcp` |

> Naming note: in python-sdk **v1** the class is `FastMCP`
> (`from mcp.server.fastmcp import FastMCP`). A later major rename exposes the same
> high-level API as `MCPServer` (`from mcp.server.mcpserver import MCPServer`). This
> project and `tasks/T-20260625-mcp-tools.md` reference **FastMCP** — use that import
> unless the pinned `mcp` version in `pyproject.toml` says otherwise. The decorator
> and `run()` semantics are identical between the two names.

## The three things you do

### 1. Define a server

```python
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("uc-analytics")   # the server name hosts display
```

### 2. Register a tool

A tool is a plain function decorated with `@mcp.tool()`. FastMCP derives the tool's
`name` from the function name, its `description` from the docstring, and its
`inputSchema` (JSON Schema) from the **type-annotated parameters**. A type-annotated
**return** (e.g. a `pydantic.BaseModel` or a `TypedDict`) generates the
`outputSchema` and a `structuredContent` result.

```python
from pydantic import BaseModel, Field

class RevenueRow(BaseModel):
    category: str
    day: str
    revenue: float
    order_count: int

@mcp.tool()
def revenue_by_category(start: str, end: str) -> list[RevenueRow]:
    """Daily revenue and order count per product category over a date range.

    Answers the E4 question: 'How much revenue did each category make per day?'
    """
    # Delegate to the SHARED query core — never reimplement the SQL here.
    from src.serving import queries
    return queries.revenue_by_category(start=start, end=end)
```

Key facts (from the tools spec):

| Tool field | Source in FastMCP | Notes |
|------------|-------------------|-------|
| `name` | function name (override: `@mcp.tool(name=...)`) | unique identifier the LLM routes to |
| `title` | `@mcp.tool(title=...)` | optional human-readable display name |
| `description` | function docstring | name the question so an LLM routes intent → tool |
| `inputSchema` | type annotations on params | JSON Schema `object`; required = params without defaults |
| `outputSchema` | annotated return type | optional; if present, results MUST conform |
| `annotations` | `@mcp.tool(annotations=...)` | hints like `readOnlyHint`; clients treat as untrusted |

### 3. Run over stdio

`mcp.run()` with **no transport argument defaults to stdio** — the transport hosts
like Claude Desktop launch and speak over a child process's stdin/stdout.

```python
if __name__ == "__main__":
    mcp.run()                      # stdio (default) — for Claude Desktop & CLI hosts
    # mcp.run(transport="streamable-http")   # HTTP surface, when a network host is needed
```

Wire it behind a Make target for this repo (`make serve-mcp` → `python -m src.serving.mcp_server`).

## Decorator surface (FastMCP)

| Decorator | Exposes | Use in THIS project |
|-----------|---------|---------------------|
| `@mcp.tool()` | a **model-controlled action** (`tools/list`, `tools/call`) | **all five analytical questions** — tools, not resources |
| `@mcp.resource("uri://{x}")` | application-controlled **data** by URI | not used here — answers are actions, not static blobs |
| `@mcp.prompt()` | a user-controlled prompt template | not used here |

> Decision rule: expose the analytical questions as **tools**. They are
> parameterized, model-invoked actions over gold, not addressable static data — see
> `concepts/tools-vs-resources.md`.

## Result & error model (what a tool returns on the wire)

- Success → `content` (unstructured, e.g. text) and, when an output schema exists,
  `structuredContent` conforming to it. Returning a typed object lets FastMCP fill both.
- Tool-execution error → result with `isError: true` (the LLM can see and react).
- Protocol error (unknown tool, bad arguments) → JSON-RPC error, not a tool result.

See `reference/tool-json-schema.md` for the exact JSON shapes.

## Cross-references

- `quick-reference.md` — this tech's index
- `reference/tool-json-schema.md` — the input/output JSON-Schema shapes
- `patterns/analytical-tool-server.md` — the full server this repo builds
- `concepts/transport-stdio-http.md` — when stdio vs Streamable HTTP
