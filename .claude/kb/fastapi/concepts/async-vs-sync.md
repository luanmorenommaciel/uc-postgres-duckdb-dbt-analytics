# Concept · Async Vs Sync

> **One-liner:** <TODO: one-line description of async-vs-sync>
> **Confidence floor:** 0.95
> **Limit:** ~150 lines. Atomic — one concept per file.

## Source of truth

- FastAPI — Concurrency and async / await: <https://fastapi.tiangolo.com/async/>
- FastAPI — path operation functions (`def` vs `async def`): <https://fastapi.tiangolo.com/async/#path-operation-functions>
- Verified against: FastAPI docs, 2026-06-25.

> Relevance to THIS project: the DuckDB Python driver used by the query core
> (`src/serving/queries.py`) is a **blocking** client. Per the FastAPI docs, a plain
> `def` path operation runs in an external threadpool so blocking I/O does not stall the
> event loop, whereas `async def` must not call blocking code directly. This concept is
> in-scope and is what the route-design pattern leans on; the body below is still a TODO.

## What it is

<!-- TODO: define the concept precisely. Ground in the official docs (cite the URL
     from this tech's reference/ entry). State what it IS before how to use it. -->

## Why it matters here

<!-- TODO: tie to THIS project — which component (C1–C8 / A1–A5 / I1–I5) or which
     acceptance criterion (AC-1…AC-6) or failure mode this concept governs. -->

## Mental model

<!-- TODO: the smallest correct picture an agent needs. A diagram or 3–5 invariants. -->

## Gotchas

<!-- TODO: the mistakes that look right. Each gotcha = one bullet + the correct move. -->

## See also

- `quick-reference.md` — this tech's index
- <!-- TODO: link related concepts/patterns with [[slug]] -->
