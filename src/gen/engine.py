from __future__ import annotations

import random
import time
from datetime import UTC, datetime

import psycopg
from faker import Faker

from src.gen import repository as repo
from src.gen.failures import REGISTRY, InjectionResult
from src.seed.factories import EcommerceFactory


class TrafficGenerator:
    def __init__(self, conn: psycopg.Connection) -> None:
        self.conn = conn
        self.factory = EcommerceFactory(Faker())

    def emit(self, count: int) -> int:
        customer_column = repo.order_customer_column(self.conn)
        customers = repo.sample_customer_ids(self.conn, min(count, 200))
        products = repo.sample_products(self.conn, min(count, 200))
        if not customers or not products:
            return 0

        columns = [customer_column, "product_id", "quantity", "unit_price", "total_amount", "status", "ordered_at"]
        rows = []
        for _ in range(count):
            customer_id = random.choice(customers)
            product = random.choice(products)
            order = self.factory.order(customer_id, product, not_before=datetime.now(UTC).replace(year=2020))
            rows.append(
                (
                    customer_id,
                    order.product_id,
                    order.quantity,
                    order.unit_price,
                    order.total_amount,
                    order.status,
                    datetime.now(UTC),
                )
            )

        placeholders = ", ".join(["%s"] * len(columns))
        with self.conn.cursor() as cur:
            cur.executemany(
                f"INSERT INTO orders ({', '.join(columns)}) VALUES ({placeholders})",
                rows,
            )
        self.conn.commit()
        return count


def run_traffic(conn: psycopg.Connection, count: int) -> int:
    inserted = TrafficGenerator(conn).emit(count)
    return inserted


def inject(conn: psycopg.Connection, key: str, record: bool = False) -> InjectionResult:
    from src.gen.failures import MultiFailureCascade, get

    failure = get(key)
    if isinstance(failure, MultiFailureCascade):
        # The cascade fires several sub-failures and owns its own ledger writes,
        # so the flag is threaded in rather than recorded again here (no double-write).
        result = failure.inject(conn, record=record)
    else:
        result = failure.inject(conn)
        if record:
            repo.record_incident(conn, result.failure, result.detail, result.detected_by)
    conn.commit()
    return result


def watch(
    conn: psycopg.Connection,
    interval: float,
    batch: int,
    failure_every: int,
    failures: list[str],
    on_event,
    record: bool = False,
) -> None:
    generator = TrafficGenerator(conn)
    pool = failures or list(REGISTRY)
    tick = 0
    while True:
        tick += 1
        generator.emit(batch)
        conn.commit()
        on_event(f"tick {tick}: +{batch} orders")
        if failure_every and tick % failure_every == 0:
            key = random.choice(pool)
            result = inject(conn, key, record=record)
            on_event(f"tick {tick}: INJECTED {result.failure} ({result.detail})")
        time.sleep(interval)
