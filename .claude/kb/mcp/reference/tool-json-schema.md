# Reference · Tool Input/Output JSON-Schema Shape

> **Scope:** The exact JSON-Schema shape of an MCP tool — `inputSchema`,
> `outputSchema`, the `tools/list` tool definition, and the `tools/call` result
> (`content` + `structuredContent`). This is what the developer agent greps when it
> needs the precise field names and the schema dialect.
> **No line limit.** This is lookup material — completeness over brevity.

## Source of truth

Every claim below traces to one of these. Update the date when you refresh.

- Tools concept (spec, 2025-06-18): <https://modelcontextprotocol.io/specification/2025-06-18/server/tools>
- SEP-2106 — schemas conform to JSON Schema 2020-12: <https://modelcontextprotocol.io/seps/2106-json-schema-2020-12>
- JSON Schema (the dialect tool schemas use): <https://json-schema.org/>
- Tools concept (docs): <https://modelcontextprotocol.io/docs/concepts/tools>
- Verified against: spec 2025-06-18 + SEP-2106, checked 2026-06-25.

## Tool definition (one entry in a `tools/list` response)

```json
{
  "name": "get_weather",
  "title": "Weather Information Provider",
  "description": "Get current weather information for a location",
  "inputSchema": {
    "type": "object",
    "properties": {
      "location": { "type": "string", "description": "City name or zip code" }
    },
    "required": ["location"]
  },
  "outputSchema": {
    "type": "object",
    "properties": {
      "temperature": { "type": "number" },
      "conditions": { "type": "string" }
    },
    "required": ["temperature", "conditions"]
  }
}
```

| Field | Required | Meaning |
|-------|----------|---------|
| `name` | yes | unique identifier the client/LLM routes to |
| `title` | no | human-readable display name |
| `description` | no (do it) | functionality; name the question so an LLM routes intent → tool |
| `inputSchema` | yes | JSON Schema for the arguments object |
| `outputSchema` | no | JSON Schema for the structured result; if present, results MUST conform |
| `annotations` | no | behavior hints (`readOnlyHint`, etc.); clients treat as **untrusted** |

## `inputSchema` — the rules

- The dialect is **JSON Schema 2020-12** (SEP-2106). You may add `$schema`.
- The top level **MUST be `"type": "object"`** — tool arguments are always an object.
- Beyond that, any valid 2020-12 keyword is allowed: `properties`, `required`,
  per-property constraints (`minimum`, `maximum`, `minLength`, `format`, `enum`),
  composition (`anyOf`, `oneOf`, `allOf`, `not`), conditionals (`if`/`then`/`else`),
  and references (`$ref`, `$defs`).
- A parameter is **required** iff it has no default — list it in `required`.

Composition example (find by id OR name):

```json
{
  "type": "object",
  "oneOf": [
    { "properties": { "id":   { "type": "string", "format": "uuid" } }, "required": ["id"] },
    { "properties": { "name": { "type": "string", "minLength": 1 } },   "required": ["name"] }
  ]
}
```

## `outputSchema` — the rules

- Also **JSON Schema 2020-12**. **No** `type: "object"` requirement — outputs can be
  any JSON value, so the schema may validate an array, an object, or a primitive.
- If a tool declares `outputSchema`: the server **MUST** return `structuredContent`
  conforming to it; the client **SHOULD** validate against it.

Array output (the common shape for analytical tools in this repo):

```json
{
  "outputSchema": {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "category":    { "type": "string" },
        "day":         { "type": "string", "format": "date" },
        "revenue":     { "type": "number" },
        "order_count": { "type": "integer" }
      },
      "required": ["category", "day", "revenue", "order_count"]
    }
  }
}
```

## `tools/call` result — `content` + `structuredContent`

A successful result carries unstructured `content` and, when an output schema
exists, `structuredContent`. For backward compatibility a tool returning structured
content **SHOULD** also serialize the JSON into a `text` content block.

```json
{
  "content": [
    { "type": "text", "text": "[{\"category\":\"books\",\"day\":\"2026-06-24\",\"revenue\":1240.5,\"order_count\":31}]" }
  ],
  "structuredContent": [
    { "category": "books", "day": "2026-06-24", "revenue": 1240.5, "order_count": 31 }
  ]
}
```

- `structuredContent` may be **any** JSON value conforming to `outputSchema`
  (object, array, or primitive) — SEP-2106 loosened it from "object only".
- `content` item types: `text`, `image`, `audio`, `resource_link`, embedded `resource`.

## Errors

| Mechanism | When | Shape |
|-----------|------|-------|
| **Tool-execution error** | business/logic/API failure inside the tool | result with `"isError": true` (LLM sees it) |
| **Protocol error** | unknown tool, invalid arguments, server fault | JSON-RPC `error` object (e.g. code `-32602`) |

## How FastMCP fills these for you

In the Python SDK you almost never hand-write these schemas:
- `inputSchema` is generated from the tool function's **type-annotated parameters**.
- `outputSchema` + `structuredContent` are generated from the **annotated return
  type** (a `pydantic.BaseModel`, `TypedDict`, or `list[...]` thereof).
See `reference/server-sdk-api.md`.

## Cross-references

- `quick-reference.md` — this tech's index
- `reference/server-sdk-api.md` — how FastMCP derives these schemas from Python types
- `patterns/tool-schema-design.md` — shaping a schema for clean LLM routing
