"""Data-access helpers for the synthetic generator.

Thin, parameterized wrappers over the source PostgreSQL database used by the
traffic generator and the defect injectors. Every query here is a single-purpose
helper: sampling reference rows, inspecting the current ``orders`` schema,
inserting orders, and reading or writing the ``injected_incidents`` ledger.
"""

from __future__ import annotations

from decimal import Decimal

import psycopg

from src.db.connection import connect


def sample_customer_ids(conn: psycopg.Connection, limit: int) -> list[int]:
    """Return a random sample of existing customer ids.

    Args:
        conn: An open PostgreSQL connection.
        limit: Maximum number of customer ids to return.

    Returns:
        Up to ``limit`` randomly ordered ``customer_id`` values.
    """
    with conn.cursor() as cur:
        cur.execute("SELECT customer_id FROM customers ORDER BY random() LIMIT %s", (limit,))
        return [row[0] for row in cur.fetchall()]


def sample_products(conn: psycopg.Connection, limit: int) -> list[tuple[int, Decimal]]:
    """Return a random sample of products with their unit prices.

    Args:
        conn: An open PostgreSQL connection.
        limit: Maximum number of products to return.

    Returns:
        Up to ``limit`` ``(product_id, unit_price)`` pairs in random order.
    """
    with conn.cursor() as cur:
        cur.execute("SELECT product_id, unit_price FROM products ORDER BY random() LIMIT %s", (limit,))
        return [(row[0], row[1]) for row in cur.fetchall()]


def latest_order(conn: psycopg.Connection) -> tuple | None:
    """Return the most recently inserted order row.

    Resolves the customer-reference column dynamically so it works whether or
    not the ``schema_drift`` defect has renamed it.

    Args:
        conn: An open PostgreSQL connection.

    Returns:
        A tuple of ``(order_id, customer_ref, product_id, quantity, unit_price,
        total_amount, status, ordered_at)`` for the highest ``order_id``, or
        ``None`` when the table is empty.
    """
    customer_column = order_customer_column(conn)
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT order_id, {customer_column}, product_id, quantity, unit_price, total_amount, status, ordered_at "
            "FROM orders ORDER BY order_id DESC LIMIT 1"
        )
        return cur.fetchone()


def order_customer_column(conn: psycopg.Connection) -> str:
    """Return the current name of the orders customer-reference column.

    The ``schema_drift`` defect renames ``customer_id`` to ``user_id``; this
    helper inspects ``information_schema`` to report whichever name is live.

    Args:
        conn: An open PostgreSQL connection.

    Returns:
        ``"customer_id"`` or ``"user_id"``, defaulting to ``"customer_id"`` when
        neither is found.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name = 'orders' AND column_name IN ('customer_id', 'user_id')"
        )
        row = cur.fetchone()
    return row[0] if row else "customer_id"


def execute(conn: psycopg.Connection, statement: str, params: tuple = ()) -> None:
    """Execute a single parameterized statement, discarding any result.

    Args:
        conn: An open PostgreSQL connection.
        statement: The SQL statement to run.
        params: Bound parameters for the statement.
    """
    with conn.cursor() as cur:
        cur.execute(statement, params)


def insert_order(conn: psycopg.Connection, columns: list[str], values: tuple) -> int:
    """Insert one order row and return its generated id.

    Args:
        conn: An open PostgreSQL connection.
        columns: The ``orders`` column names being written, in order.
        values: The values matching ``columns`` positionally.

    Returns:
        The ``order_id`` assigned to the newly inserted row.
    """
    cols = ", ".join(columns)
    placeholders = ", ".join(["%s"] * len(columns))
    with conn.cursor() as cur:
        cur.execute(f"INSERT INTO orders ({cols}) VALUES ({placeholders}) RETURNING order_id", values)
        return cur.fetchone()[0]


def record_incident(conn: psycopg.Connection, failure_key: str, detail: str) -> None:
    """Append a ground-truth row to the ``injected_incidents`` ledger.

    Args:
        conn: An open PostgreSQL connection.
        failure_key: The defect's registry key.
        detail: Human-readable description of what was corrupted.
    """
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO injected_incidents (failure_key, detail) VALUES (%s, %s)",
            (failure_key, detail),
        )


def count_incidents(conn: psycopg.Connection, failure_key: str) -> int:
    """Count recorded incidents for a given defect key.

    Args:
        conn: An open PostgreSQL connection.
        failure_key: The defect's registry key to count.

    Returns:
        The number of ledger rows recorded for ``failure_key``.
    """
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM injected_incidents WHERE failure_key = %s", (failure_key,))
        return cur.fetchone()[0]


def session() -> psycopg.Connection:
    """Open a new connection to the source PostgreSQL database.

    Returns:
        A fresh :class:`psycopg.Connection`; the caller is responsible for
        closing it (typically via a ``with`` block).
    """
    return connect()
