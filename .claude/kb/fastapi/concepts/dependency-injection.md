# Concept · Dependency Injection

> **One-liner:** <TODO: one-line description of dependency-injection>
> **Confidence floor:** 0.95
> **Limit:** ~150 lines. Atomic — one concept per file.

## Source of truth

- FastAPI — Dependencies: <https://fastapi.tiangolo.com/tutorial/dependencies/>
- FastAPI — Dependencies with `yield`: <https://fastapi.tiangolo.com/tutorial/dependencies/dependencies-with-yield/>
- Verified against: FastAPI docs, 2026-06-25.

> Relevance to THIS project: a `Depends(...)` is the idiomatic way to share the
> read-only warehouse handle and common query params (date range, run id) across the gold
> endpoints without each handler re-opening `connect_read_only()`. In-scope but light —
> the serving layer is thin, so DI here is optional sugar, not load-bearing. Body is TODO.

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
