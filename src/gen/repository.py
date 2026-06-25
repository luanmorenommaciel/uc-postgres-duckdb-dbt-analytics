from __future__ import annotations

from decimal import Decimal

import psycopg

from src.db.connection import connect


def sample_customer_ids(conn: psycopg.Connection, limit: int) -> list[int]:
    with conn.cursor() as cur:
        cur.execute("SELECT customer_id FROM customers ORDER BY random() LIMIT %s", (limit,))
        return [row[0] for row in cur.fetchall()]


def sample_products(conn: psycopg.Connection, limit: int) -> list[tuple[int, Decimal]]:
    with conn.cursor() as cur:
        cur.execute("SELECT product_id, unit_price FROM products ORDER BY random() LIMIT %s", (limit,))
        return [(row[0], row[1]) for row in cur.fetchall()]


def latest_order(conn: psycopg.Connection) -> tuple | None:
    customer_column = order_customer_column(conn)
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT order_id, {customer_column}, product_id, quantity, unit_price, total_amount, status, ordered_at "
            "FROM orders ORDER BY order_id DESC LIMIT 1"
        )
        return cur.fetchone()


def order_customer_column(conn: psycopg.Connection) -> str:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_name = 'orders' AND column_name IN ('customer_id', 'user_id')"
        )
        row = cur.fetchone()
    return row[0] if row else "customer_id"


def execute(conn: psycopg.Connection, statement: str, params: tuple = ()) -> None:
    with conn.cursor() as cur:
        cur.execute(statement, params)


def insert_order(conn: psycopg.Connection, columns: list[str], values: tuple) -> int:
    cols = ", ".join(columns)
    placeholders = ", ".join(["%s"] * len(columns))
    with conn.cursor() as cur:
        cur.execute(f"INSERT INTO orders ({cols}) VALUES ({placeholders}) RETURNING order_id", values)
        return cur.fetchone()[0]


def record_incident(conn: psycopg.Connection, failure_key: str, detail: str, detected_by: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO injected_incidents (failure_key, detail, detected_by) VALUES (%s, %s, %s)",
            (failure_key, detail, detected_by),
        )


def count_incidents(conn: psycopg.Connection, failure_key: str) -> int:
    with conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM injected_incidents WHERE failure_key = %s", (failure_key,))
        return cur.fetchone()[0]


def session() -> psycopg.Connection:
    return connect()
