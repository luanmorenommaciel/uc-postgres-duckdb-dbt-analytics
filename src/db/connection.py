"""PostgreSQL connection and bulk-write helpers for the source database.

Centralises how the rest of the project reaches the e-commerce source Postgres:
connection info is read from the environment (with sane local defaults), and a
small set of helpers cover the bulk operations the seeder and generators need
(batched ``INSERT ... RETURNING``, row counts, and a full-truncate reset).

All SQL parameters are passed as bound placeholders. Table and primary-key
identifiers are interpolated only from internal constants, never user input.
"""

from __future__ import annotations

import os
from collections.abc import Sequence

import psycopg


def conninfo() -> dict[str, object]:
    """Build psycopg connection keyword arguments from the environment.

    Each field falls back to a local-development default when its
    ``POSTGRES_*`` environment variable is unset, so no credentials are
    hardcoded for non-default deployments.

    Returns:
        A mapping suitable for ``psycopg.connect(**conninfo())``.
    """
    return {
        "host": os.environ.get("POSTGRES_HOST", "localhost"),
        "port": int(os.environ.get("POSTGRES_PORT", "5432")),
        "dbname": os.environ.get("POSTGRES_DB", "ecommerce"),
        "user": os.environ.get("POSTGRES_USER", "postgres"),
        "password": os.environ.get("POSTGRES_PASSWORD", "postgres"),
    }


def connect() -> psycopg.Connection:
    """Open a new Postgres connection in explicit-transaction mode.

    The connection uses ``autocommit=False`` so callers control commit
    boundaries; it is intended for use as a context manager.
    """
    return psycopg.connect(**conninfo(), autocommit=False)


def insert_returning_ids(
    conn: psycopg.Connection,
    table: str,
    columns: Sequence[str],
    rows: Sequence[tuple],
) -> list[int]:
    """Bulk-insert rows and return their generated primary-key ids in order.

    Runs a single ``executemany`` ``INSERT ... RETURNING`` and collects the
    returned id from each result set. The primary-key column is derived from
    the table name by convention (``orders`` -> ``order_id``).

    Args:
        conn: Open connection to insert through (not committed here).
        table: Target table name (internal constant, interpolated as-is).
        columns: Column names matching the order of values in each row.
        rows: Row tuples to insert; values are bound as parameters.

    Returns:
        The generated ids, one per inserted row, in insertion order. Empty
        when ``rows`` is empty.
    """
    if not rows:
        return []
    cols = ", ".join(columns)
    placeholders = ", ".join(["%s"] * len(columns))
    pk = f"{table[:-1]}_id"
    statement = f"INSERT INTO {table} ({cols}) VALUES ({placeholders}) RETURNING {pk}"
    ids: list[int] = []
    with conn.cursor() as cur:
        cur.executemany(statement, rows, returning=True)
        while True:
            ids.append(cur.fetchone()[0])
            if not cur.nextset():
                break
    return ids


def count(conn: psycopg.Connection, table: str) -> int:
    """Return the total row count for a table.

    Args:
        conn: Open connection to query through.
        table: Table name (internal constant, interpolated as-is).

    Returns:
        The number of rows currently in the table.
    """
    with conn.cursor() as cur:
        cur.execute(f"SELECT count(*) FROM {table}")
        return cur.fetchone()[0]


def truncate_all(conn: psycopg.Connection) -> None:
    """Empty all source tables and reset their identity sequences.

    Truncates payments, orders, products, and customers together with
    ``RESTART IDENTITY CASCADE`` so a fresh seed starts from clean ids.
    """
    with conn.cursor() as cur:
        cur.execute("TRUNCATE payments, orders, products, customers RESTART IDENTITY CASCADE")
