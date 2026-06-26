# Reference · Response Models

> **Scope:** The exact FastAPI `response_model` surface and the Pydantic v2 serialization
> options used to shape what a read-only gold endpoint returns. This is grep material —
> accuracy over prose.
> **No line limit.** This is lookup material — completeness over brevity.

## Source of truth

Every claim below is traceable to one of these. Update the date when you refresh.

- FastAPI — Response Model tutorial: <https://fastapi.tiangolo.com/tutorial/response-model/>
- FastAPI — root docs: <https://fastapi.tiangolo.com/>
- Pydantic v2: <https://docs.pydantic.dev/latest/>
- Pydantic v2 — serialization (`model_dump` / exclude options): <https://docs.pydantic.dev/latest/concepts/serialization/>
- Starlette `TestClient` (used by `fastapi.testclient.TestClient`): <https://www.starlette.io/testclient/>
- Verified against: FastAPI docs, 2026-06-25.

## How a response model is declared

Two ways. Prefer the **return-type annotation** when the returned object matches the
schema; use the **`response_model=` decorator parameter** when the returned object is a
different type (e.g. a `dict` or a DuckDB row tuple) but you still want FastAPI to
validate/filter/document the output. If both are present, **`response_model` takes
priority**. Source: <https://fastapi.tiangolo.com/tutorial/response-model/#response-model-priority>.

```python
from pydantic import BaseModel
from fastapi import FastAPI

app = FastAPI()

class RevenueRow(BaseModel):
    category: str
    day: str          # tz-aware timestamp already CAST to text at the SQL boundary
    revenue: float
    order_count: int

# Return-type form (preferred when the returned object IS the schema):
@app.get("/revenue/by-category")
async def revenue_by_category() -> list[RevenueRow]:
    ...

# response_model= form (when you return dicts/rows, not model instances):
@app.get("/revenue/by-category", response_model=list[RevenueRow])
async def revenue_by_category2():
    return [{"category": "books", "day": "2026-06-24", "revenue": 1.0, "order_count": 3}]
```

FastAPI uses the model to **convert and filter** the output: fields not declared on the
model are dropped from the response. Source:
<https://fastapi.tiangolo.com/tutorial/response-model/#fastapi-data-filtering>.

## `response_model` decorator-parameter cheatsheet

All are parameters of the *path-operation decorator* (`@app.get(...)`), NOT of the
handler function. Source: <https://fastapi.tiangolo.com/tutorial/response-model/>.

| Parameter | Type | Effect |
|---|---|---|
| `response_model` | a Pydantic type, `list[Model]`, etc. | Validate + filter + document the output against this schema. Takes priority over the return annotation. |
| `response_model=None` | `None` | Disable response-model generation (keep the return annotation for tooling only; needed when the annotation is not a valid Pydantic type, e.g. a `Response \| dict` union). |
| `response_model_exclude_unset` | `bool` (default `False`) | Omit fields that were never explicitly set (left at their default). |
| `response_model_exclude_defaults` | `bool` (default `False`) | Omit fields whose value equals the field default. |
| `response_model_exclude_none` | `bool` (default `False`) | Omit fields whose value is `None`. |
| `response_model_include` | `set[str]` (or list/tuple) | Whitelist of attribute names to keep. |
| `response_model_exclude` | `set[str]` (or list/tuple) | Blacklist of attribute names to drop. |
| `response_model_by_alias` | `bool` (default `True`) | Serialize using field aliases. |

Notes (source: response-model tutorial, "Response Model encoding parameters"):

- `exclude_unset` keeps explicitly-set values even when they equal the default —
  Pydantic distinguishes "set to the default value" from "left unset".
- `include`/`exclude` take a `set`; a `list`/`tuple` is accepted and coerced to a set.
- `include`/`exclude`/`by_alias` do NOT change the OpenAPI/JSON-Schema shown in `/docs`
  (it still reflects the full model) — prefer separate input/output models for that.
  Source: <https://fastapi.tiangolo.com/tutorial/response-model/#response-model-include-and-response-model-exclude>.

## Input vs output models

When the input carries fields the output must not (the classic password case), declare a
separate output model and pass it as `response_model=` (or use inheritance so the return
type is a supertype and FastAPI still filters). Source:
<https://fastapi.tiangolo.com/tutorial/response-model/#add-an-output-model>.

For this repo the read-only gold endpoints have **no request body** — the "input" is
query/path params (see `concepts/pydantic-boundaries.md`). The output model is the only
boundary that needs a Pydantic schema.

## Pydantic v2 serialization options (`model_dump` / `model_dump_json`)

FastAPI's `response_model_exclude_*` map onto Pydantic v2's serialization keywords.
Source: <https://docs.pydantic.dev/latest/concepts/serialization/>.

| Pydantic v2 keyword | Mirrors FastAPI param | Effect |
|---|---|---|
| `exclude_unset=True` | `response_model_exclude_unset` | drop fields never set |
| `exclude_defaults=True` | `response_model_exclude_defaults` | drop fields equal to default |
| `exclude_none=True` | `response_model_exclude_none` | drop `None`-valued fields |
| `include={...}` / `exclude={...}` | `response_model_include`/`exclude` | field whitelist / blacklist |
| `by_alias=True` | `response_model_by_alias` | serialize by alias |
| `mode="json"` | (implicit in FastAPI) | produce JSON-safe primitives (FastAPI does this via `jsonable_encoder`) |

Migration notes (Pydantic v1 → v2): `.dict()` → `model_dump()`, `.json()` →
`model_dump_json()`, `class Config` → `model_config = ConfigDict(...)`, validators use
`@field_validator` / `@model_validator`. Source: <https://docs.pydantic.dev/latest/migration/>.

## The tz-aware timestamp gotcha (this repo)

The gold marts hold **tz-aware** `TIMESTAMP WITH TIME ZONE` columns. DuckDB requires
`pytz` to materialize those into Python `datetime`s; if the query core hands a raw
tz-aware value to the response model the endpoint can 500 at serialization. The fix lives
in the SQL, not the model: **CAST timestamps to text or epoch at the SQL boundary** in
`src/serving/queries.py`, so the Pydantic field is a plain `str`/`int`/`float`. Then
`json.dumps(response)` and `jsonable_encoder` never touch a tz-aware object. See
`kb/duckdb/quick-reference.md` for the DuckDB-side detail and
`concepts/pydantic-boundaries.md` for where this lands in the model.

## Cross-references

- `quick-reference.md` — this tech's index
- `concepts/pydantic-boundaries.md` — what types belong at the request/response edge
- `patterns/route-design.md` — the one-question read-only endpoint shape that returns these models
- `kb/duckdb/quick-reference.md` — the pytz / tz-aware cast at the SQL boundary
