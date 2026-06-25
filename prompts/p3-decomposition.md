# Converge · Pass 3 — Decomposition

**Engine:** Claude Code (Auto Mode) — same session as Pass 2, so the understanding carries over.
**Inputs:** the Pass 2 understanding (in session) · the tech-spec · the repo (`src/`).
**Output:** `sketch/duckdb-dbt-med-arch.plan` and `sketch/fast-api-mcp.plan` — the two plans.
**Gate:** the system is split at its real seam — transformation vs. serving; each plan lists features, components, dependencies, and build order; the serving plan names the interface it consumes (the gold tables).

Three steps: **decompose → plan the medallion → plan the serving layer.**

> Teaching note: we don't guess the boundaries — the architecture reveals them. The brownfield already ends at `raw.*`; everything above it splits cleanly into *shaping the data* (dbt bronze→silver→gold) and *exposing it* (FastAPI/MCP over gold). Pass 3 follows that seam. Plan altitude only — features and components, not atomic tasks (that's Pass 5).

---

## Step 1 · Decompose — find the seam

```text
From everything we just understood, split what we're building into its top-level
components. Don't plan yet — just give me the decomposition and justify the
boundary: why does the split fall HERE? The brownfield ends at DuckDB raw.*;
group what comes above it and tell me how the pieces depend on each other.
```

*Expected:* two components along the natural seam —
**Medallion** (dbt bronze→silver→gold over `raw.*`, deterministic transformation) and **Serving** (FastAPI/MCP over the gold tables, the read interface). Serving depends on Medallion; Medallion depends on the existing `raw.*` landing.

## Step 2 · Plan the medallion

```text
Write sketch/duckdb-dbt-med-arch.plan — the plan for the dbt medallion over
DuckDB raw.*. Include: the layers (bronze cleans/types raw.*, silver conforms and
applies business rules, gold builds the serving-ready marts), what each does, the
dependencies between them, and the build order. Tie components back to the
tech-spec's requirements where they apply (freshness, the metrics gold must
expose). Name the data-quality tests that prove each layer. Plan altitude — no
atomic tasks yet, no model SQL. Keep it tight and skimmable.
```

## Step 3 · Plan the serving layer

```text
Now write sketch/fast-api-mcp.plan — the plan for the FastAPI/MCP layer. Same
shape: features/components (the endpoints and the MCP tools, what each returns),
dependencies, build order. Crucially, name the INTERFACE it consumes from the
medallion — exactly which GOLD tables/columns each endpoint and tool reads — so
the seam between the two plans is explicit and the serving layer never reaches
below gold. Plan altitude, no tasks, no handler code.
```

---

## Gate — confirm before leaving Pass 3

- [ ] Two plans exist: `sketch/duckdb-dbt-med-arch.plan`, `sketch/fast-api-mcp.plan`.
- [ ] The split follows the real seam (transformation vs. serving), and the boundary is justified.
- [ ] Each plan lists features/components, dependencies, and a sane build order.
- [ ] Components trace back to the tech-spec's requirements where they apply.
- [ ] `fast-api-mcp.plan` names the gold-table interface it consumes — it never reads below gold.
- [ ] Plan altitude held — no atomic tasks, no SQL, no handler code yet.

When these hold, the two plans are the input to Pass 4, where a different engine attacks them.

---

### Notes

- **Two plans, not one.** A dbt transformation pipeline and a serving API are different kinds of work and decompose differently. Forcing them into one plan hides the seam that keeps them buildable independently.
- **The seam is the gold tables.** The serving layer depends on the medallion, but only through the named gold interface — not by reading `raw.*` or `silver.*` directly. That contract is what lets the two be built (and tested) on their own.
- **Auto Mode earns its keep here** — decomposition is exploratory; let it read across the spec and repo and draft both plans, then you gate.
- **Still no decomposition into tasks.** Plans describe *what* and *in what order*. Cutting them into atomic, self-verifying units is Pass 5 — keep the altitude.
