from __future__ import annotations

import os
from collections.abc import Sequence

import psycopg


def conninfo() -> dict[str, object]:
    return {
        "host": os.environ.get("POSTGRES_HOST", "localhost"),
        "port": int(os.environ.get("POSTGRES_PORT", "5432")),
        "dbname": os.environ.get("POSTGRES_DB", "ecommerce"),
        "user": os.environ.get("POSTGRES_USER", "postgres"),
        "password": os.environ.get("POSTGRES_PASSWORD", "postgres"),
    }


def connect() -> psycopg.Connection:
    return psycopg.connect(**conninfo(), autocommit=False)


def insert_returning_ids(
    conn: psycopg.Connection,
    table: str,
    columns: Sequence[str],
    rows: Sequence[tuple],
) -> list[int]:
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
    with conn.cursor() as cur:
        cur.execute(f"SELECT count(*) FROM {table}")
        return cur.fetchone()[0]


def truncate_all(conn: psycopg.Connection) -> None:
    with conn.cursor() as cur:
        cur.execute("TRUNCATE payments, orders, products, customers RESTART IDENTITY CASCADE")
