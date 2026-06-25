"""Orchestration for synthetic traffic and defect injection.

Provides the runtime that drives the generator: a :class:`TrafficGenerator` that
streams normal orders into PostgreSQL, an :func:`inject` entry point that fires a
single defect, and a :func:`watch` loop that interleaves traffic with periodic
injections. Whether injected defects are recorded to the ``injected_incidents``
ledger is controlled by the ``record`` flag and is silent by default.
"""

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
    """Streams realistic, well-formed orders into the source database."""

    def __init__(self, conn: psycopg.Connection) -> None:
        """Bind the generator to a connection and an order factory.

        Args:
            conn: An open PostgreSQL connection used for all inserts.
        """
        self.conn = conn
        self.factory = EcommerceFactory(Faker())

    def emit(self, count: int) -> int:
        """Insert ``count`` synthetic orders for random customers and products.

        Samples reference customers and products, builds plausible orders via
        the factory, and bulk-inserts them. Resolves the customer column
        dynamically so it tolerates prior schema drift.

        Args:
            count: Number of orders to generate and insert.

        Returns:
            The number of orders inserted; ``0`` when no customers or products
            are available to reference.
        """
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
    """Emit a one-off batch of normal orders.

    Args:
        conn: An open PostgreSQL connection.
        count: Number of orders to insert.

    Returns:
        The number of orders actually inserted.
    """
    inserted = TrafficGenerator(conn).emit(count)
    return inserted


def inject(conn: psycopg.Connection, key: str, record: bool = False) -> InjectionResult:
    """Inject a single defect by key and commit the change.

    The cascade defect drives several sub-injectors and owns its own ledger
    writes, so the ``record`` flag is threaded into it rather than recorded
    again here; all other defects are recorded by this function when requested.

    Args:
        conn: An open PostgreSQL connection.
        key: The registry key of the defect to inject.
        record: When true, persist the result to the ``injected_incidents``
            ledger. Silent by default.

    Returns:
        The :class:`InjectionResult` describing the corruption performed.
    """
    from src.gen.failures import MultiFailureCascade, get

    failure = get(key)
    if isinstance(failure, MultiFailureCascade):
        # The cascade fires several sub-failures and owns its own ledger writes,
        # so the flag is threaded in rather than recorded again here (no double-write).
        result = failure.inject(conn, record=record)
    else:
        result = failure.inject(conn)
        if record:
            repo.record_incident(conn, result.failure, result.detail)
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
    """Continuously stream traffic and inject defects on a fixed cadence.

    Runs until interrupted, emitting a batch of orders each tick and injecting a
    random defect from ``failures`` (or the full registry) every
    ``failure_every`` ticks.

    Args:
        conn: An open PostgreSQL connection.
        interval: Seconds to sleep between ticks.
        batch: Number of orders to emit per tick.
        failure_every: Inject a defect every Nth tick; ``0`` disables injection.
        failures: Candidate defect keys to draw from; empty means all of them.
        on_event: Callback invoked with a human-readable message per event.
        record: When true, record injected defects to the ledger. Silent by
            default.
    """
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
