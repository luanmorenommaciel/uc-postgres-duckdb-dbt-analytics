# Spec: Analytical Backbone — dbt over DuckDB

| | |
| --- | --- |
| **Status** | Draft for review |
| **Derived from** | `docs/brd-analytical-backbone.pdf` (BRD, approved statement of the problem) |
| **Format** | SpecKit-inspired feature spec — falsifiable requirements, measurable success criteria |
| **Answers** | BRD requirements R1–R6 |
| **Prescribes** | The architecture shape (dbt models over DuckDB, Postgres untouched) — never the implementation details |

> **The contract in one line:** the storefront's PostgreSQL stays the untouched
> system of record; a separate analytical lane (DuckDB + dbt) ingests from it,
> models it, and answers the business's questions in seconds — and every
> requirement below is provable by a gate that runs on every build.

---

## 1 · Why (from the BRD)

One PostgreSQL instance serves the storefront **and** analytics. At 50K
orders/day the workloads contend: a core analytical query takes **12 minutes**
where the business needs **< 5 seconds** (BRD §4). The BRD authorizes a
structural fix — give analytics its own lane — under two non-negotiables
(BRD §9):

- **No storefront disruption** — the pipeline must never degrade `public.*`.
- **Source of truth unchanged** — Postgres remains the system of record; the
  analytical store is derived, never authoritative.

## 2 · What we are building

```
Postgres (OLTP, read-only tap)          DuckDB (OLAP)                 Consumers
┌──────────────────────────┐   sync    ┌──────────────────────┐
│ customers · products     │ ────────► │ raw → staging → marts │ ───► defined question set,
│ orders · payments        │  ≤ 5 min  │        (dbt)          │      < 5 s, self-serve
└──────────────────────────┘           └──────────────────────┘
```

- **Ingestion**: incremental sync of the four source tables into DuckDB.
- **Staging** (`stg_*`): 1:1 with source, typed, renamed, deduplicated.
- **Marts**: `dim_customers`, `dim_products`, `fct_orders`, `fct_daily_revenue`.
- **Gates**: dbt tests + reconciliation checks wired into `make test` —
  the same gate CI runs, the same gate an agent must pass.

## 3 · Functional requirements

Every FR is falsifiable — a named check can pass or fail it — and traces to a
BRD requirement.

| ID | Requirement | Traces to | Falsified by |
| --- | --- | --- | --- |
| **FR-001** | All four source tables land in DuckDB with **freshness ≤ 5 min** (event → queryable). | R3 | source-freshness check |
| **FR-002** | The pipeline reads Postgres through a **read-only role**; zero DDL/DML against `public.*`; no measurable degradation of the storefront under peak. | R1 | role audit + load test |
| **FR-003** | Staging models are 1:1 with source, typed and deduplicated on the natural key (`customer_id`, `product_id`, `ordered_at`). | R4 | uniqueness tests |
| **FR-004** | The defined question set (§5) answers in **p95 < 5 s / p99 < 15 s** straight from the marts, no engineering ticket needed. | R2, R4 | latency harness on the question set |
| **FR-005** | Data-quality gates run on **every build** and fail loudly (error, not warn): keys not-null + unique, referential integrity, accepted status values, non-negative amounts and quantities. | R5 | `dbt build` exit code |
| **FR-006** | **Reconciliation**: for any closed day, row counts and `SUM(total_amount)` match Postgres vs marts exactly. A silent mismatch is a failed build. | R5, R6 | reconciliation singular test |
| **FR-007** | **Source-contract check**: if a source column the marts depend on disappears or is renamed (e.g. `orders.customer_id`), the build fails at the contract — never by silently producing NULLs downstream. | R5 | contract test |

## 4 · The eval — how this spec proves itself

The gate is one command. It is the same gate for a human, for CI at 3 a.m.,
and for an agent that just wrote code:

```bash
make test        # dbt build (models + tests) + reconciliation + contract checks
```

**Pass** = every FR's check green. **Fail** = the work does not ship. There is
no "looks right" state.

## 5 · The self-serve question set (R4)

The marts must answer these directly, with no new report build:

1. Daily revenue, and revenue by product category / customer segment / country.
2. Average order value and orders per day, trend over any window.
3. Top-N customers by lifetime value.
4. Payment coverage: orders whose payments do not sum to `total_amount`.
5. Orphan detection: orders without a valid customer; payments without a valid order.
6. Day-over-day volume anomalies (spike/drop flagged for investigation).

## 6 · Edge cases — mapped to the repo's failure modes

This spec was written against the terrain: the repo ships 14 injectable
defects (`make failures`). Each gate-class defect names the check that must
catch it. **This table is the spec's answer key.**

| Failure mode (`make inject FAILURE=…`) | Class | Expected defense |
| --- | --- | --- |
| `schema_drift` (customer_id → user_id) | gate | FR-007 contract check fails the build |
| `missing_customer` (NULL customer_id) | gate | FR-005 referential-integrity test |
| `orphan_payment` (payment → ghost order) | gate | FR-005 relationship test |
| `negative_price` | gate | FR-005 non-negative amount test |
| `invalid_quantity` (qty ≤ 0) | gate | FR-005 positive-quantity test |
| `duplicate_order` (exact re-insert) | gate | FR-003 natural-key dedup + uniqueness test |
| `malformed_data` (garbage status) | gate | FR-005 accepted-values test |
| `destructive_fix` (bulk overwrite of totals) | gate | FR-006 reconciliation mismatch |
| `late_arrival` (order backdated 45 days) | gate | FR-001/FR-006 — backfill window must capture it; reconciliation confirms |
| `volume_spike` | investigation | §5.6 anomaly flag (warn, not fail) |
| `slow_source` (lock on orders) | investigation | FR-001 freshness alert fires; storefront unaffected (FR-002) |
| `ambiguous_anomaly` · `multi_failure_cascade` · `recurring_incident` | investigation | root-cause scenarios — the loop investigates, the gates scope the blast radius |

## 7 · Success criteria (from BRD §8)

| SC | Outcome | Current → Target |
| --- | --- | --- |
| SC-001 | Query latency p95 on question set | 12 min → **< 5 s** |
| SC-002 | Query latency p99 | 28 min → **< 15 s** |
| SC-003 | Data freshness | 24 h → **≤ 5 min** |
| SC-004 | Analytical availability | 97.8% → **99.5%** |
| SC-005 | Silent data incidents reaching a dashboard | — → **0** (gates fail loudly first) |

## 8 · Out of scope (this phase)

Personalization/ML use cases, storefront changes, new data sources, changes to
order/payment business logic (BRD §7). The analytical lane is additive only.

## 9 · Open questions

1. Ingestion cadence under sustained peak — is ≤ 5 min freshness held at 75K orders/day?
2. Retention: how much history do the marts keep hot in DuckDB before archival?
3. Who owns triage when an investigation-class alert fires out of hours?

---

*Spec style: SpecKit-inspired (github/spec-kit). Alternatives evaluated for
this repo: OpenSpec (change-proposal workflow, strong for brownfield deltas)
and AgentSpec (specs as executable agent contracts). Start simple; graduate
when the change volume demands it.*
