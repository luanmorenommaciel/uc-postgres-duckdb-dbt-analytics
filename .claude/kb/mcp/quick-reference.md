# Model Context Protocol — Quick Reference

> **Purpose:** Fast lookup for Model Context Protocol. The first read for both the
> architect and developer agents, and for any closer working a file in this tech.
> **Hard limit:** 100 lines. Deep material lives in `concepts/`, `patterns/`, `reference/`.

## Identity

The **Model Context Protocol (MCP)** is an open protocol that lets a host (Claude
Desktop, an IDE, an agent) discover and call **tools** a server exposes over a
JSON-RPC transport (stdio or Streamable HTTP). In THIS project MCP is the **second
transport of Component B (Serve)** — the agent-callable surface beside the FastAPI
HTTP surface. It exposes **one typed tool per frozen E4 question**
(`revenue_by_category`, `customer_segments`, `order_health`,
`payment_reconciliation`, `freshness`), each wrapping the **same**
`src/serving/queries.py` core its sibling endpoint uses. That is the literal **E4
self-serve** requirement: a non-engineer asks in natural language, an agent routes
to a tool, gets a correct answer, no new report is built. Same hard boundary as the
API — **read-only, gold-only, latest published `_gold_run_id` generation**, no reach
below gold, no writable connection. **The one thing an agent must never get wrong:**
do NOT reimplement a query in the MCP layer — call `src.serving.queries`. A forked
query is how a tool and its endpoint silently drift apart; same core ⇒ same answer.
Source of truth: <https://modelcontextprotocol.io/> .

## Decision flow

```text
┌─────────────────────────────────────────────────────────────┐
│  Model Context Protocol — AGENT FLOW                         │
├─────────────────────────────────────────────────────────────┤
│  1. CLASSIFY → architect (plan) or developer (ship)?        │
│  2. LOAD     → this KB, then the matching concept/pattern    │
│  3. VALIDATE → KB + MCP agreement matrix                     │
│  4. ACT      → cite the specific doc per decision/finding    │
│  5. VERIFY   → tests/assertions green; grounded in docs      │
└─────────────────────────────────────────────────────────────┘
```

## Index

| Kind | Doc | Read it when |
|------|-----|--------------|
| concept | `concepts/mcp-protocol-model.md` | you need the host/client/server + JSON-RPC model |
| concept | `concepts/tools-vs-resources.md` | deciding tool (model-controlled action) vs resource (data) |
| concept | `concepts/transport-stdio-http.md` | choosing/wiring stdio vs Streamable HTTP transport |
| pattern | `patterns/analytical-tool-server.md` | **the pattern THIS repo uses** — one tool per question over the shared query core |
| pattern | `patterns/tool-schema-design.md` | shaping a tool's input/output schema for clean LLM routing |
| pattern | `patterns/nl-to-sql-tool.md` | mapping NL intent → a fixed analytical tool (not free-form SQL) |
| reference | `reference/server-sdk-api.md` | exact FastMCP / python-sdk signatures: define server, register tool, run over stdio |
| reference | `reference/tool-json-schema.md` | exact `inputSchema` / `outputSchema` / tool-result shapes |

## Cross-references

| Need | Where |
|------|-------|
| Project conventions every task follows | `CLAUDE.md` at repo root |
| Cross-tech code-quality universals | `kb/code-quality/quick-reference.md` |
| The shared query core every tool must reuse | `kb/fastapi/quick-reference.md`, `src/serving/queries.py` |
| Architecture plans this tech serves | `sketch/fast-api-mcp.plan`, `sketch/duckdb-dbt-med-arch.plan` |
| The task that builds this layer | `tasks/T-20260625-mcp-tools.md` |
