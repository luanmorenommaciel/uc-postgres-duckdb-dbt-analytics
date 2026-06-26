# Pattern · Background Tasks

> **Solves:** <TODO: problem statement for background-tasks>
> **Limit:** ~200 lines. One reusable pattern, production-grade.

## Source of truth

- FastAPI — Background Tasks: <https://fastapi.tiangolo.com/tutorial/background-tasks/>
- Verified against: FastAPI docs, 2026-06-25.

## NOT USED IN THIS PROJECT

> **This pattern is NOT used by this repo's serving layer (see `CLAUDE.md`).** Component B
> is a thin, read-only, gold-only lookup surface: each endpoint validates params, calls
> the query core, serializes a finite result, and returns synchronously. There is no
> deferred work, no post-response side effect, no write path — so there is nothing for a
> `BackgroundTasks` to do. Do **not** build this speculatively. If a future requirement
> genuinely needs post-response work, that is a scope change to be decided against
> `sketch/fast-api-mcp.plan`, not a pattern to pre-wire here. The TODO body below is left
> intentionally unfilled.

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
