from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import psycopg

from src.gen import repository as repo


def _order_columns(conn: psycopg.Connection) -> list[str]:
    return [
        repo.order_customer_column(conn),
        "product_id",
        "quantity",
        "unit_price",
        "total_amount",
        "status",
        "ordered_at",
    ]


@dataclass(frozen=True, slots=True)
class InjectionResult:
    failure: str
    detail: str
    detected_by: str


class Failure:
    key: str = ""
    summary: str = ""
    detected_by: str = ""
    unlocks: str = ""

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        raise NotImplementedError


def _disable_order_checks(conn: psycopg.Connection) -> None:
    customer_column = repo.order_customer_column(conn)
    repo.execute(conn, "ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_unit_price_check")
    repo.execute(conn, "ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_quantity_check")
    repo.execute(conn, "ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_total_amount_check")
    repo.execute(conn, f"ALTER TABLE orders ALTER COLUMN {customer_column} DROP NOT NULL")


class NegativePrice(Failure):
    key = "negative_price"
    summary = "Insert an order with a negative unit price and total."
    detected_by = "Data Profiler"
    unlocks = "base crew: Data Profiler tool (QueryDuckDB / ProfileTable)"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        _disable_order_checks(conn)
        customer_id = repo.sample_customer_ids(conn, 1)[0]
        product_id, _ = repo.sample_products(conn, 1)[0]
        price = Decimal("-49.99")
        order_id = repo.insert_order(
            conn,
            _order_columns(conn),
            (customer_id, product_id, 1, price, price, "placed", datetime.now(UTC)),
        )
        return InjectionResult(self.key, f"order_id={order_id} unit_price={price}", self.detected_by)


class MissingCustomer(Failure):
    key = "missing_customer"
    summary = "Insert an order with a NULL customer_id (orphaned order)."
    detected_by = "Data Profiler"
    unlocks = "base crew: null/constraint profiling"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        _disable_order_checks(conn)
        customer_column = repo.order_customer_column(conn)
        product_id, unit_price = repo.sample_products(conn, 1)[0]
        repo.execute(
            conn,
            f"INSERT INTO orders ({customer_column}, product_id, quantity, unit_price, total_amount, status, "
            "ordered_at) VALUES (NULL, %s, %s, %s, %s, %s, %s)",
            (product_id, 1, unit_price, unit_price, "placed", datetime.now(UTC)),
        )
        return InjectionResult(self.key, f"inserted order with {customer_column}=NULL", self.detected_by)


class InvalidQuantity(Failure):
    key = "invalid_quantity"
    summary = "Insert an order with a non-positive quantity."
    detected_by = "Data Profiler"
    unlocks = "base crew: range/domain profiling"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        _disable_order_checks(conn)
        customer_id = repo.sample_customer_ids(conn, 1)[0]
        product_id, unit_price = repo.sample_products(conn, 1)[0]
        order_id = repo.insert_order(
            conn,
            _order_columns(conn),
            (customer_id, product_id, -5, unit_price, Decimal("0.00"), "placed", datetime.now(UTC)),
        )
        return InjectionResult(self.key, f"order_id={order_id} quantity=-5", self.detected_by)


class DuplicateOrder(Failure):
    key = "duplicate_order"
    summary = "Re-insert the most recent order as an exact duplicate row."
    detected_by = "Data Profiler"
    unlocks = "base crew: uniqueness profiling"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        latest = repo.latest_order(conn)
        if latest is None:
            return InjectionResult(self.key, "no orders to duplicate", self.detected_by)
        _, customer_id, product_id, quantity, unit_price, total_amount, status, ordered_at = latest
        order_id = repo.insert_order(
            conn,
            _order_columns(conn),
            (customer_id, product_id, quantity, unit_price, total_amount, status, ordered_at),
        )
        return InjectionResult(self.key, f"duplicated into order_id={order_id}", self.detected_by)


class LateArrival(Failure):
    key = "late_arrival"
    summary = "Insert an order backdated 45 days (late-arriving data)."
    detected_by = "Data Profiler"
    unlocks = "base crew: freshness profiling"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        customer_id = repo.sample_customer_ids(conn, 1)[0]
        product_id, unit_price = repo.sample_products(conn, 1)[0]
        backdated = datetime.now(UTC) - timedelta(days=45)
        order_id = repo.insert_order(
            conn,
            _order_columns(conn),
            (customer_id, product_id, 1, unit_price, unit_price, "delivered", backdated),
        )
        return InjectionResult(self.key, f"order_id={order_id} ordered_at={backdated.date()}", self.detected_by)


class VolumeSpike(Failure):
    key = "volume_spike"
    summary = "Insert a sudden burst of orders (volume anomaly)."
    detected_by = "Data Profiler"
    unlocks = "base crew: volume/statistical profiling"

    def __init__(self, burst: int = 500) -> None:
        self.burst = burst

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        columns = _order_columns(conn)
        customers = repo.sample_customer_ids(conn, 50) or [None]
        products = repo.sample_products(conn, 50)
        now = datetime.now(UTC)
        rows = []
        for index in range(self.burst):
            customer_id = customers[index % len(customers)]
            product_id, unit_price = products[index % len(products)]
            rows.append((customer_id, product_id, 1, unit_price, unit_price, "placed", now))
        placeholders = ", ".join(["%s"] * len(columns))
        with conn.cursor() as cur:
            cur.executemany(
                f"INSERT INTO orders ({', '.join(columns)}) VALUES ({placeholders})",
                rows,
            )
        return InjectionResult(self.key, f"inserted {self.burst} orders in one burst", self.detected_by)


class SchemaDrift(Failure):
    key = "schema_drift"
    summary = "Rename orders.customer_id -> user_id (breaks downstream models)."
    detected_by = "Log Analyst"
    unlocks = "base crew: Log Analyst tool (ReadDagsterLogs / ReadDbtRunResults)"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        current = repo.order_customer_column(conn)
        if current == "user_id":
            return InjectionResult(self.key, "already drifted (column is user_id)", self.detected_by)
        repo.execute(conn, "ALTER TABLE orders RENAME COLUMN customer_id TO user_id")
        return InjectionResult(self.key, "orders.customer_id renamed to user_id", self.detected_by)


class OrphanPayment(Failure):
    key = "orphan_payment"
    summary = "Insert a payment referencing a non-existent order_id."
    detected_by = "Data Profiler"
    unlocks = "base crew: cross-table referential profiling"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        repo.execute(conn, "ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_order_id_fkey")
        repo.execute(
            conn,
            "INSERT INTO payments (order_id, method, amount, status, paid_at) VALUES (%s, %s, %s, %s, %s)",
            (999999999, "credit_card", Decimal("10.00"), "captured", datetime.now(UTC)),
        )
        return InjectionResult(self.key, "payment inserted for order_id=999999999", self.detected_by)


class RecurringIncident(Failure):
    key = "recurring_incident"
    summary = "Re-inject negative prices repeatedly so the same incident appears many times."
    detected_by = "Data Profiler"
    unlocks = "CrewAI Memory: recognise a repeat offender ('seen 3x this week') instead of cold-starting"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        _disable_order_checks(conn)
        columns = _order_columns(conn)
        customer_id = repo.sample_customer_ids(conn, 1)[0]
        product_id, _ = repo.sample_products(conn, 1)[0]
        price = Decimal("-19.99")
        order_id = repo.insert_order(
            conn,
            columns,
            (customer_id, product_id, 1, price, price, "placed", datetime.now(UTC)),
        )
        seen = repo.count_incidents(conn, self.key) + 1
        return InjectionResult(self.key, f"order_id={order_id} (occurrence #{seen})", self.detected_by)


class AmbiguousAnomaly(Failure):
    key = "ambiguous_anomaly"
    summary = "Revenue drops via cancellations AND a price cut at once (two plausible root causes)."
    detected_by = "Data Profiler"
    unlocks = "CrewAI Knowledge/RAG: consult a runbook to disambiguate competing root causes"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        repo.execute(
            conn,
            "UPDATE orders SET status = 'cancelled' WHERE order_id IN "
            "(SELECT order_id FROM orders WHERE status <> 'cancelled' ORDER BY order_id DESC LIMIT 200)",
        )
        repo.execute(
            conn,
            "UPDATE products SET unit_price = round(unit_price * 0.5, 2) WHERE product_id IN "
            "(SELECT product_id FROM products ORDER BY random() LIMIT 20)",
        )
        return InjectionResult(self.key, "200 orders cancelled + 20 products price-cut 50%", self.detected_by)


class DestructiveFix(Failure):
    key = "destructive_fix"
    summary = "Corrupt total_amount on many rows so the only fix is a bulk overwrite."
    detected_by = "Data Profiler"
    unlocks = "CrewAI Human-in-the-loop: a destructive remediation must pause for approval"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        repo.execute(
            conn,
            "UPDATE orders SET total_amount = 0 WHERE order_id IN "
            "(SELECT order_id FROM orders ORDER BY order_id DESC LIMIT 300)",
        )
        return InjectionResult(self.key, "zeroed total_amount on 300 orders (bulk fix required)", self.detected_by)


class MalformedData(Failure):
    key = "malformed_data"
    summary = "Inject garbage into status fields (free-text noise the agent must summarise)."
    detected_by = "Data Profiler"
    unlocks = "CrewAI Guardrails + output_pydantic: force a typed, validated post-mortem"

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        garbage = "���/NULL/<script>/0x00 ¿status?"
        repo.execute(
            conn,
            "UPDATE orders SET status = %s WHERE order_id IN "
            "(SELECT order_id FROM orders ORDER BY order_id DESC LIMIT 25)",
            (garbage,),
        )
        return InjectionResult(self.key, "wrote garbage status to 25 orders", self.detected_by)


class SlowSource(Failure):
    key = "slow_source"
    summary = "Hold a lock on orders to make the source slow/unresponsive for a while."
    detected_by = "Log Analyst"
    unlocks = "CrewAI tool reliability: max_retry, timeouts and fallbacks on flaky tools"

    def __init__(self, seconds: int = 8) -> None:
        self.seconds = seconds

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        with conn.cursor() as cur:
            cur.execute("SET lock_timeout = '1s'")
            cur.execute(f"SELECT pg_sleep({self.seconds})")
        return InjectionResult(self.key, f"source stalled for {self.seconds}s", self.detected_by)


class MultiFailureCascade(Failure):
    key = "multi_failure_cascade"
    summary = "Fire schema drift + nulls + a volume spike together (mixed incident)."
    detected_by = "Manager"
    unlocks = "CrewAI Flows + conditional routing: send each failure type to the right squad"

    def inject(self, conn: psycopg.Connection, record: bool = False) -> InjectionResult:
        parts: list[str] = []
        for key in ("missing_customer", "volume_spike", "schema_drift"):
            result = REGISTRY[key].inject(conn)
            # Silent by default: only write the ground-truth ledger when the
            # operator opts in (gen inject --record / make inject RECORD=1).
            if record:
                repo.record_incident(conn, result.failure, result.detail, result.detected_by)
            parts.append(result.failure)
        return InjectionResult(self.key, "cascade: " + ", ".join(parts), self.detected_by)


REGISTRY: dict[str, Failure] = {
    failure.key: failure
    for failure in (
        NegativePrice(),
        MissingCustomer(),
        InvalidQuantity(),
        DuplicateOrder(),
        LateArrival(),
        VolumeSpike(),
        SchemaDrift(),
        OrphanPayment(),
        RecurringIncident(),
        AmbiguousAnomaly(),
        DestructiveFix(),
        MalformedData(),
        SlowSource(),
        MultiFailureCascade(),
    )
}


def get(key: str) -> Failure:
    if key not in REGISTRY:
        available = ", ".join(sorted(REGISTRY))
        raise KeyError(f"unknown failure '{key}'. available: {available}")
    return REGISTRY[key]
