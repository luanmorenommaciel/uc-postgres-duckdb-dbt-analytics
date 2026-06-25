"""C2 landing engine — full-refresh Postgres -> DuckDB ``raw.raw_*``.

This module lands the four source entities (customers, products, orders,
payments) into ``raw.raw_*`` using DuckDB's ``postgres`` extension:

  1. Resolve the orders schema-drift column ONCE in Python via psycopg, mirroring
     :func:`src.gen.repository.order_customer_column` exactly (see
     :func:`resolve_order_customer_column` below). This drives BOTH the templated
     identifier in the orders projection AND the bound ``_schema_drift`` boolean,
     so they can never disagree.
  2. ``ATTACH`` Postgres READ-ONLY through a DuckDB-managed temporary secret (the
     password never enters the ATTACH string nor any error output — DuckDB's docs
     warn an inline-DSN connection string can be printed on connection error).
  3. ``CREATE OR REPLACE TABLE raw.raw_<entity> AS SELECT ...`` per entity, copying
     the source columns 1:1 (DuckDB infers ``NUMERIC(p,s)`` -> ``DECIMAL(p,s)`` and
     ``TIMESTAMPTZ`` -> ``TIMESTAMP WITH TIME ZONE`` losslessly) and computing the
     three trailing C2 lineage columns.
  4. ``DETACH`` and drop the secret in a ``finally`` so a mid-run error still
     cleans up.

Contract preserved from the prior Dagster ``platform.ingestion.assets`` module:
  - Money is ``DECIMAL`` (no float coercion — money columns are never cast).
  - Timestamps are ``TIMESTAMPTZ`` (tz-aware UTC). ``_ingested_at`` is a single
    run-level ``datetime.now(UTC)`` BOUND as ``$ingested_at`` (never ``now()`` in
    SQL, which would strip the tz to a naive ``TIMESTAMP``) so every row in a run
    shares the exact C8/AC-3 freshness anchor.
  - ``_source_watermark`` is this run's high-watermark: ``(SELECT max(<wm>) FROM
    pg.public.<table>)``, identical on every row, NULL on an empty source.
  - ``_schema_drift`` exists ONLY on ``raw_orders``; the other three tables do not
    carry it (the source ``_DDL`` asymmetry is preserved).

Defects are NEVER dropped or repaired here — that is silver's job; defects land
intact in ``raw.*`` (the U3 detection-seam assumption: defects survive into raw
unfiltered).

ASSUMPTIONS (R4 / U3 discipline):
  - This is a *full refresh*: no incremental/watermark state, no ``ON CONFLICT`` /
    MERGE, no lookback window, no PK-completeness arm. ``CREATE OR REPLACE`` makes
    re-runs idempotent (modulo ``_ingested_at``, which advances by design).
  - No concurrent ``schema_drift`` injection happens during a ``make land`` run
    (the drift column is resolved before ATTACH; a race after that would surface
    as a loud error, which is acceptable for a single-operator demo).

The DuckDB connection is read/**write** (it writes ``raw.*``); the **ATTACH** is
``READ_ONLY`` (the Postgres source is never modified) — that is the R3 one-way
dependency in code.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from platform.warehouse.connection import connect
from typing import TYPE_CHECKING

import psycopg

from src.db.connection import conninfo

if TYPE_CHECKING:
    import duckdb


# --------------------------------------------------------------------------- #
# Constants                                                                    #
# --------------------------------------------------------------------------- #

RAW_SCHEMA = "raw"
PG_ALIAS = "pg"
SECRET_NAME = "pg_landing"

# Statement timeout (ms) for the short drift-probe psycopg connection, in the
# spirit of platform.ingestion.resources.PostgresResource — so the probe can
# never hang the demo on a stalled source.
_PROBE_STATEMENT_TIMEOUT_MS = 10_000


# --------------------------------------------------------------------------- #
# Per-entity spec (drives the SQL templating)                                  #
# --------------------------------------------------------------------------- #


@dataclass(frozen=True, slots=True)
class EntitySpec:
    """Static description of how one source table maps into ``raw`` (full refresh).

    Trimmed from the prior Dagster ``EntitySpec``: no incremental/PK-arm fields,
    since landing is full-refresh. ``watermark_col`` is still needed to compute
    ``_source_watermark``.
    """

    entity: str  # 'customers' | 'products' | 'orders' | 'payments'
    source_table: str  # Postgres table name (public schema)
    pk: str  # source primary key (for ORDER BY determinism only)
    watermark_col: str  # timestamp column -> max() feeds _source_watermark
    # STABLE raw-slot names, IN ORDER, copied straight from the source SELECT
    # (i.e. excluding the C2-stamped trailing columns). For orders the
    # "customer_id" slot is the stable name; the live source column is resolved
    # at runtime and SELECTed AS customer_id.
    source_columns: tuple[str, ...]


CUSTOMERS = EntitySpec(
    entity="customers",
    source_table="customers",
    pk="customer_id",
    watermark_col="created_at",
    source_columns=("customer_id", "full_name", "email", "country", "city", "segment", "created_at"),
)

PRODUCTS = EntitySpec(
    entity="products",
    source_table="products",
    pk="product_id",
    watermark_col="created_at",
    source_columns=("product_id", "sku", "name", "category", "unit_price", "cost", "created_at"),
)

ORDERS = EntitySpec(
    entity="orders",
    source_table="orders",
    pk="order_id",
    watermark_col="ordered_at",
    source_columns=(
        "order_id",
        "customer_id",
        "product_id",
        "quantity",
        "unit_price",
        "total_amount",
        "status",
        "ordered_at",
    ),
)

PAYMENTS = EntitySpec(
    entity="payments",
    source_table="payments",
    pk="payment_id",
    watermark_col="paid_at",
    source_columns=("payment_id", "order_id", "method", "amount", "status", "paid_at"),
)

# Landing order: dimensions first, then facts. ORDER matters only for readable
# output; full-refresh tables are independent.
ALL_SPECS: tuple[EntitySpec, ...] = (CUSTOMERS, PRODUCTS, ORDERS, PAYMENTS)


# --------------------------------------------------------------------------- #
# Result type                                                                  #
# --------------------------------------------------------------------------- #


@dataclass(frozen=True, slots=True)
class LandResult:
    """What one entity's landing produced."""

    entity: str
    row_count: int
    source_watermark: str | None  # max watermark landed, as ISO text (None if empty source)
    schema_drift: bool  # orders only; False for the rest


# --------------------------------------------------------------------------- #
# schema_drift resolution (orders only) — mirrors src.gen.repository EXACTLY    #
# --------------------------------------------------------------------------- #


def resolve_order_customer_column(conn: psycopg.Connection) -> str:
    """Return the live source column for the order->customer link.

    EXACT verbatim mirror of :func:`src.gen.repository.order_customer_column`
    (the C2 "mirror exactly" contract). Returns ``'user_id'`` after the
    ``schema_drift`` failure renamed the column, else ``'customer_id'``. Landing
    selects this column ``AS customer_id`` into the stable raw slot.

    Copied here (rather than imported) to keep ``platform.landing`` free of a
    runtime import dependency on ``src.gen`` (which carries faker/generator
    weight); the dependency graph stays ``platform.* -> src.db`` only.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name = 'orders' AND column_name IN ('customer_id', 'user_id')"
        )
        row = cur.fetchone()
    return row[0] if row else "customer_id"


def _resolve_drift() -> tuple[str, bool]:
    """Open a short read-only psycopg connection, resolve the orders column, close.

    Returns ``(customer_col, schema_drift)`` where ``schema_drift`` is True iff
    the live column drifted to ``user_id``. The probe is bounded by a statement
    timeout so a stalled source cannot hang the run.
    """
    info = conninfo()
    conn = psycopg.connect(**info, autocommit=True)
    try:
        with conn.cursor() as cur:
            # SET does not accept bind parameters; the timeout is a server-side
            # int constant, never user input (R8).
            cur.execute("SET default_transaction_read_only = on")
            cur.execute(f"SET statement_timeout = {int(_PROBE_STATEMENT_TIMEOUT_MS)}")
        live_col = resolve_order_customer_column(conn)
    finally:
        conn.close()
    return live_col, (live_col != "customer_id")


# --------------------------------------------------------------------------- #
# DuckDB session setup: extension, secret, ATTACH                              #
# --------------------------------------------------------------------------- #


def _q(value: str) -> str:
    """Escape a single-quoted SQL string literal by doubling single quotes.

    DuckDB escapes single quotes inside string literals by repeating them (per
    the postgres-extension docs). ``CREATE SECRET`` does not accept bind
    parameters for its option values, so the env-derived constants are
    interpolated and defensively escaped here. Values originate from
    :func:`src.db.connection.conninfo` (env vars), never from user input (R8).
    """
    return value.replace("'", "''")


def _attach_postgres_read_only(con: duckdb.DuckDBPyConnection) -> None:
    """Install/load the extension, create a temporary secret, ATTACH READ-ONLY.

    Uses the DuckDB-managed secret form (Section 6 of the design): the password
    stays out of the ATTACH string and out of error output. The secret is
    ``TEMPORARY`` (the default) so nothing persists in the warehouse file. The
    ATTACH is ``READ_ONLY`` and scoped to the ``public`` schema only.
    """
    con.execute("INSTALL postgres")
    con.execute("LOAD postgres")

    info = conninfo()
    con.execute(
        f"CREATE OR REPLACE SECRET {SECRET_NAME} ("
        "  TYPE postgres,"
        f"  HOST '{_q(str(info['host']))}',"
        f"  PORT {int(info['port'])},"
        f"  DATABASE '{_q(str(info['dbname']))}',"
        f"  USER '{_q(str(info['user']))}',"
        f"  PASSWORD '{_q(str(info['password']))}'"
        ")"
    )
    # Empty connection string => use everything from the secret. READ_ONLY is the
    # R3 linchpin: landing can never write the source. SCHEMA 'public' narrows the
    # attachment to the one schema we read.
    con.execute(f"ATTACH '' AS {PG_ALIAS} (TYPE postgres, READ_ONLY, SECRET {SECRET_NAME}, SCHEMA 'public')")


def _detach_postgres(con: duckdb.DuckDBPyConnection) -> None:
    """Release the PG connection and drop the temporary secret (belt-and-suspenders)."""
    con.execute(f"DETACH {PG_ALIAS}")
    con.execute(f"DROP SECRET IF EXISTS {SECRET_NAME}")


# --------------------------------------------------------------------------- #
# Per-entity landing                                                           #
# --------------------------------------------------------------------------- #


def _build_projection(spec: EntitySpec, customer_col: str | None) -> str:
    """Build the SELECT projection of the STABLE source columns, in order.

    For orders, the (possibly drifted) live customer column is templated into the
    identifier slot and aliased back to ``customer_id``. Identifiers cannot be
    bound parameters in any SQL engine, so the live column — resolved from
    ``information_schema`` (never user input) — is templated into the query text.
    """
    if spec.entity == "orders":
        if customer_col is None:  # pragma: no cover - defensive; land_all always passes it
            raise ValueError("orders landing requires a resolved customer_col")
        cols: list[str] = []
        for col in spec.source_columns:
            if col == "customer_id":
                cols.append(f"{customer_col} AS customer_id")
            else:
                cols.append(col)
        return ",\n    ".join(cols)
    return ",\n    ".join(spec.source_columns)


def land_entity(
    con: duckdb.DuckDBPyConnection,
    spec: EntitySpec,
    *,
    ingested_at: datetime,
    customer_col: str | None = None,
    schema_drift: bool = False,
) -> LandResult:
    """Land one entity into ``raw.raw_<entity>`` on an already-attached connection.

    Runs ``CREATE OR REPLACE TABLE ... AS SELECT`` (idempotent full refresh),
    binding ``$ingested_at`` (and ``$schema_drift`` for orders), then reads the
    landed row count and source watermark for the :class:`LandResult`.

    Args:
        con: A read/write warehouse connection with Postgres already ATTACHed as
            ``pg`` (read-only) and the ``raw`` schema created.
        spec: The entity to land.
        ingested_at: The single run-level tz-aware UTC anchor, bound as
            ``$ingested_at``.
        customer_col: The live orders customer column (``'customer_id'`` |
            ``'user_id'``). Required for orders; ignored otherwise.
        schema_drift: Bound as ``$schema_drift`` for orders only.
    """
    target = f"{RAW_SCHEMA}.raw_{spec.entity}"
    source = f"{PG_ALIAS}.public.{spec.source_table}"
    projection = _build_projection(spec, customer_col)
    watermark_subquery = f"(SELECT max({spec.watermark_col}) FROM {source})"

    params: dict[str, object] = {"ingested_at": ingested_at}

    if spec.entity == "orders":
        params["schema_drift"] = bool(schema_drift)
        sql = (
            f"CREATE OR REPLACE TABLE {target} AS\n"
            "SELECT\n"
            f"    {projection},\n"
            "    $ingested_at AS _ingested_at,\n"
            f"    {watermark_subquery} AS _source_watermark,\n"
            "    $schema_drift AS _schema_drift\n"
            f"FROM {source}\n"
            f"ORDER BY {spec.pk}"
        )
    else:
        sql = (
            f"CREATE OR REPLACE TABLE {target} AS\n"
            "SELECT\n"
            f"    {projection},\n"
            "    $ingested_at AS _ingested_at,\n"
            f"    {watermark_subquery} AS _source_watermark\n"
            f"FROM {source}\n"
            f"ORDER BY {spec.pk}"
        )

    con.execute(sql, params)

    row_count = con.execute(f"SELECT count(*) FROM {target}").fetchone()[0]
    # Read the watermark back as text: it is only used for the run summary, and
    # casting to VARCHAR avoids materializing a tz-aware TIMESTAMP into Python
    # (which would pull in the optional `pytz` dependency). The stored
    # _source_watermark column stays TIMESTAMPTZ for downstream (dbt) consumers.
    watermark = con.execute(f"SELECT CAST(max(_source_watermark) AS VARCHAR) FROM {target}").fetchone()[0]

    return LandResult(
        entity=spec.entity,
        row_count=int(row_count),
        source_watermark=watermark,
        schema_drift=bool(schema_drift) if spec.entity == "orders" else False,
    )


# --------------------------------------------------------------------------- #
# Orchestration                                                                #
# --------------------------------------------------------------------------- #


def land_all(con: duckdb.DuckDBPyConnection | None = None) -> dict[str, LandResult]:
    """Full-refresh every ``raw.raw_*`` table. Returns ``{entity: LandResult}``.

    Opens (and owns/closes) a read/write warehouse connection when ``con`` is
    None; otherwise uses the caller's connection and does not close it (lets tests
    and a future orchestrator share a handle).

    Sequence:
      1. Resolve orders schema drift once (short read-only psycopg probe).
      2. ``ingested_at = datetime.now(UTC)`` — one anchor for the whole run.
      3. ATTACH Postgres read-only, create the ``raw`` schema.
      4. Land all four entities via :func:`land_entity`.
      5. ``finally``: DETACH + drop secret; close the connection only if opened here.

    Idempotent (``CREATE OR REPLACE``); a failure mid-run leaves already-landed
    tables intact and propagates loudly (no catch-and-swallow).
    """
    # (1) Resolve drift once, before any ATTACH, so the identifier and the bound
    # boolean derive from a single source and can never disagree.
    customer_col, schema_drift = _resolve_drift()

    # (2) One UTC wall-clock instant stamped on every row of every table this run
    # — the non-negotiable C8/AC-3 freshness anchor.
    ingested_at = datetime.now(UTC)

    owns_connection = con is None
    if con is None:
        # Writers leave read_only=False; connect() ensures the parent dir for the
        # write path. The single-writer invariant is honoured by the orchestration
        # contract (land THEN dbt, serialized).
        con = connect(read_only=False)

    results: dict[str, LandResult] = {}
    try:
        # (3) Attach the source read-only and ensure the raw schema exists.
        _attach_postgres_read_only(con)
        con.execute(f"CREATE SCHEMA IF NOT EXISTS {RAW_SCHEMA}")

        # (4) Land each entity; pass drift inputs only to orders.
        for spec in ALL_SPECS:
            if spec.entity == "orders":
                results[spec.entity] = land_entity(
                    con,
                    spec,
                    ingested_at=ingested_at,
                    customer_col=customer_col,
                    schema_drift=schema_drift,
                )
            else:
                results[spec.entity] = land_entity(con, spec, ingested_at=ingested_at)
    finally:
        # (5) Always release the source connection and remove the secret, even on
        # a mid-run error. Then close the warehouse handle only if we opened it.
        try:
            _detach_postgres(con)
        finally:
            if owns_connection:
                con.close()

    return results
