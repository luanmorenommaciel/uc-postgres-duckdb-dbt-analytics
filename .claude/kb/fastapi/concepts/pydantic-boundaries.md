# Concept · Pydantic Boundaries

> **One-liner:** Pydantic models live only at the edges of an endpoint — typing the
> incoming params and the outgoing JSON — never inside the gold query core.
> **Confidence floor:** 0.95
> **Limit:** ~150 lines. Atomic — one concept per file.

## Source of truth

- FastAPI — query params: <https://fastapi.tiangolo.com/tutorial/query-params/>
- FastAPI — query param validation: <https://fastapi.tiangolo.com/tutorial/query-params-str-validations/>
- FastAPI — response model: <https://fastapi.tiangolo.com/tutorial/response-model/>
- Pydantic v2: <https://docs.pydantic.dev/latest/>
- Verified against: FastAPI docs, 2026-06-25.

## What it is

A **boundary** is where untyped, external-shaped data crosses into (or out of) your code.
FastAPI gives an endpoint exactly two boundaries and asks Pydantic/typing to police both:

1. **Request boundary** — path and query parameters declared as typed function arguments.
   FastAPI parses, validates, and coerces them; a bad value yields an automatic `422`
   (or `400` if you raise it) before your code runs. Source:
   <https://fastapi.tiangolo.com/tutorial/query-params-str-validations/>.
2. **Response boundary** — the `response_model` (or return annotation). FastAPI validates,
   **filters** to the declared fields, and JSON-encodes the output. Source:
   <https://fastapi.tiangolo.com/tutorial/response-model/#fastapi-data-filtering>.

Between those two boundaries the code is plain Python over DuckDB rows — no Pydantic. The
query core (`src/serving/queries.py`) returns `list[dict]`; the model lives in the
endpoint, not the core. This keeps the same core reusable by the MCP transport, which
frames its own boundary differently.

## Why it matters here

The serving layer (Component B) has **no request body** — it is read-only lookup, so the
only request boundary is query/path params (date ranges, segment filters). The response
boundary is where the project's correctness and its E2/E3 guarantees become visible:

- The response model names exactly the gold columns the question returns (mirrors the
  per-mart contract in `sketch/fast-api-mcp.plan`). A column not in the gold contract
  cannot appear in the model — it's a new-mart request to Component A, not a deeper read.
- The response boundary is where the **tz-aware timestamp** trap is contained. The gold
  marts hold `TIMESTAMP WITH TIME ZONE`; DuckDB needs `pytz` to materialize those into
  Python. The query core CASTs them to text/epoch at the SQL edge, so the Pydantic field
  is a plain `str`/`int`/`float` and JSON encoding never touches a tz-aware object. If a
  model field is typed `datetime` and fed a raw tz-aware value, the endpoint 500s. This is
  task anti-pattern #3 in `T-20260625-api-fastapi.md`. See `kb/duckdb/quick-reference.md`.

## Mental model

```text
        REQUEST boundary                          RESPONSE boundary
   (typed params, FastAPI         core            (response_model, FastAPI
    validates → 422/400)      (plain dicts)         filters + JSON-encodes)
        │                          │                        │
  start: str|None ──▶  queries.revenue_by_category(...) ──▶ list[RevenueRow] ──▶ JSON
        │                          │                        │
   no request body          no Pydantic here          str/int fields only
                                                       (timestamps CAST in SQL)
```

Invariants:

1. Pydantic appears at the endpoint edges only; the query core returns plain rows.
2. Every response-model field maps 1:1 to a declared gold column.
3. Timestamp fields are `str`/`int` (CAST in SQL), never `datetime`, to dodge the pytz trap.
4. Request validation is the only place a `4xx` originates; the core assumes valid input.

## Gotchas

- **Typing a response field as `datetime`.** Looks correct, 500s at request time because
  the value arrives tz-aware from DuckDB. → Type it `str` and CAST in the SQL.
- **Building a Pydantic model inside the query core.** Couples the core to one transport
  and breaks tool/endpoint parity. → Core returns `list[dict]`; the model lives in `api.py`.
- **Adding a request body / `POST` to "filter more."** Serving is read-only lookup; the
  request boundary is query params only. A richer filter is a new gold mart, not a body.
- **Letting extra gold columns leak through.** Without a `response_model`, every selected
  column ships. → Declare the model so FastAPI filters to the contract's fields. Source:
  <https://fastapi.tiangolo.com/tutorial/response-model/#fastapi-data-filtering>.
- **Assuming `response_model_include`/`exclude` changes the docs.** It doesn't — the
  OpenAPI schema still shows the full model. → Use a dedicated output model instead.

## See also

- `quick-reference.md` — this tech's index
- `reference/response-models.md` — exact `response_model` / Pydantic v2 serialization options
- `patterns/route-design.md` — the endpoint shape these boundaries sit on
- `kb/duckdb/quick-reference.md` — the pytz / tz-aware CAST at the SQL boundary
