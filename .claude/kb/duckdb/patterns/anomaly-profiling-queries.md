# Pattern · Anomaly Profiling Queries

> **Solves:** <TODO: problem statement for anomaly-profiling-queries>
> **Limit:** ~200 lines. One reusable pattern, production-grade.

## Source of truth

- `SUMMARIZE` (per-column profiling stats): https://duckdb.org/docs/guides/meta/summarize
- Aggregate functions (count, min/max, quantiles): https://duckdb.org/docs/sql/functions/aggregates
- Approximate aggregates (`approx_count_distinct`, `approx_quantile`): https://duckdb.org/docs/sql/functions/aggregates
- Sampling (`USING SAMPLE`): https://duckdb.org/docs/sql/samples
- See also: `reference/sql-dialect-notes.md`

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
