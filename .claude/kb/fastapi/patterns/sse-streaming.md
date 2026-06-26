# Pattern · Sse Streaming

> **Solves:** <TODO: problem statement for sse-streaming>
> **Limit:** ~200 lines. One reusable pattern, production-grade.

## Source of truth

- FastAPI — Custom Response / `StreamingResponse`: <https://fastapi.tiangolo.com/advanced/custom-response/>
- Starlette — responses (`StreamingResponse`): <https://www.starlette.io/responses/>
- Verified against: FastAPI docs, 2026-06-25.

## NOT USED IN THIS PROJECT

> **This pattern is NOT used by this repo's serving layer (see `CLAUDE.md`).** Component B
> answers each frozen question with a single, finite JSON document — a lookup over a
> pre-aggregated gold mart that fits in one response body. There is no long-running
> generation, no token stream, no incremental result set, so there is no reason to return
> a `StreamingResponse` or Server-Sent Events. Streaming would also undercut the E2
> mechanism (lookups in seconds over pre-shaped gold). Do **not** build this
> speculatively. A streaming requirement would be a scope change decided against
> `sketch/fast-api-mcp.plan`. The TODO body below is left intentionally unfilled.

## Problem

<!-- TODO: the concrete situation this pattern addresses, in THIS project's terms. -->

## Pattern

<!-- TODO: the production code sample. Real, runnable, idiomatic for this tech.
     This is the developer agent's reference implementation — make it correct,
     not illustrative. Ground in the official docs. -->

```text
<TODO: code>
```

## Why this shape

<!-- TODO: the trade-offs. Why this and not the obvious alternative. -->

## Anti-patterns

<!-- TODO: the wrong versions of this pattern + why they bite. -->

## Verify

<!-- TODO: how an agent confirms it applied the pattern correctly (test, assertion,
     EXPLAIN plan, eval against injected_incidents ground truth, etc.). -->

## See also

- `quick-reference.md` — this tech's index
- <!-- TODO: link related concepts/patterns with [[slug]] -->
