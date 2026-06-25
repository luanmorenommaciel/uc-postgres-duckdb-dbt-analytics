"""Defect injectors for the synthetic order pipeline.

Each :class:`Failure` corrupts one or more tables in a specific, reproducible
way so the downstream data-quality and schema checks have something concrete to
catch. The module is intentionally self-contained: it knows *what* defect it is
writing and *which* table/column it touches, and nothing about who or what later
consumes the corrupted data.

The :data:`REGISTRY` maps a stable string key to a singleton injector. Callers
look one up with :func:`get`, then call :meth:`Failure.inject` against an open
PostgreSQL connection. Injectors return an :class:`InjectionResult` describing
what was done; recording that result to the ``injected_incidents`` ledger is the
caller's choice (see :mod:`src.gen.engine`).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import psycopg

from src.gen import repository as repo


def _order_columns(conn: psycopg.Connection) -> list[str]:
    """Return the insertable ``orders`` columns in a fixed order.

    The customer-reference column is resolved dynamically because the
    ``schema_drift`` defect may have renamed ``customer_id`` to ``user_id``;
    every other column name is constant.

    Args:
        conn: An open PostgreSQL connection used to inspect the current schema.

    Returns:
        The ordered column names suitable for an ``INSERT INTO orders`` value
        tuple produced by the injectors in this module.
    """
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
    """Immutable record of a single defect injection.

    Attributes:
        failure: The :attr:`Failure.key` of the injector that produced this
            result.
        detail: A short human-readable description of exactly what was
            corrupted (ids, counts, column names), suitable for logging and for
            the ``injected_incidents`` ledger.
    """

    failure: str
    detail: str


class Failure:
    """Base class for a reproducible data defect injector.

    Subclasses declare a stable :attr:`key` and a human-readable
    :attr:`summary`, then implement :meth:`inject` to corrupt the database in a
    single, well-defined way.

    Attributes:
        key: Stable identifier used as the registry key and ledger value.
        summary: One-line description of the defect for listings and help text.
    """

    key: str = ""
    summary: str = ""

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Apply this defect against ``conn`` and describe what was done.

        Args:
            conn: An open PostgreSQL connection. The injector issues its writes
                here; committing is the caller's responsibility.

        Returns:
            An :class:`InjectionResult` naming this failure and detailing the
            specific corruption performed.

        Raises:
            NotImplementedError: Always, on the base class; subclasses override.
        """
        raise NotImplementedError


def _disable_order_checks(conn: psycopg.Connection) -> None:
    """Drop the ``orders`` value constraints that would reject bad rows.

    Several injectors deliberately write out-of-range or NULL values that the
    table's ``CHECK`` and ``NOT NULL`` constraints would otherwise reject. This
    helper removes those guards so the defect can land. The constraint drops use
    ``IF EXISTS`` so the helper is idempotent across repeated injections.

    Args:
        conn: An open PostgreSQL connection with permission to alter ``orders``.
    """
    customer_column = repo.order_customer_column(conn)
    repo.execute(conn, "ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_unit_price_check")
    repo.execute(conn, "ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_quantity_check")
    repo.execute(conn, "ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_total_amount_check")
    repo.execute(conn, f"ALTER TABLE orders ALTER COLUMN {customer_column} DROP NOT NULL")


class NegativePrice(Failure):
    """Insert an ``orders`` row whose ``unit_price`` and ``total_amount`` are negative.

    Corrupts the ``orders`` table by adding a single placed order priced below
    zero, violating the non-negative money invariant.
    """

    key = "negative_price"
    summary = "Insert an order with a negative unit price and total."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Insert one order with a negative unit price and total.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` reporting the new ``order_id`` and price.
        """
        _disable_order_checks(conn)
        customer_id = repo.sample_customer_ids(conn, 1)[0]
        product_id, _ = repo.sample_products(conn, 1)[0]
        price = Decimal("-49.99")
        order_id = repo.insert_order(
            conn,
            _order_columns(conn),
            (customer_id, product_id, 1, price, price, "placed", datetime.now(UTC)),
        )
        return InjectionResult(self.key, f"order_id={order_id} unit_price={price}")


class MissingCustomer(Failure):
    """Insert an ``orders`` row with a NULL customer reference (orphaned order).

    Corrupts the ``orders`` table with a row whose customer column is NULL,
    breaking the not-null and referential expectation on that column.
    """

    key = "missing_customer"
    summary = "Insert an order with a NULL customer_id (orphaned order)."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Insert one order whose customer column is NULL.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` naming the column that was set to NULL.
        """
        _disable_order_checks(conn)
        customer_column = repo.order_customer_column(conn)
        product_id, unit_price = repo.sample_products(conn, 1)[0]
        repo.execute(
            conn,
            f"INSERT INTO orders ({customer_column}, product_id, quantity, unit_price, total_amount, status, "
            "ordered_at) VALUES (NULL, %s, %s, %s, %s, %s, %s)",
            (product_id, 1, unit_price, unit_price, "placed", datetime.now(UTC)),
        )
        return InjectionResult(self.key, f"inserted order with {customer_column}=NULL")


class InvalidQuantity(Failure):
    """Insert an ``orders`` row with a non-positive ``quantity``.

    Corrupts the ``orders`` table with a row whose quantity is negative,
    violating the positive-quantity domain rule.
    """

    key = "invalid_quantity"
    summary = "Insert an order with a non-positive quantity."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Insert one order with a negative quantity.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` reporting the new ``order_id``.
        """
        _disable_order_checks(conn)
        customer_id = repo.sample_customer_ids(conn, 1)[0]
        product_id, unit_price = repo.sample_products(conn, 1)[0]
        order_id = repo.insert_order(
            conn,
            _order_columns(conn),
            (customer_id, product_id, -5, unit_price, Decimal("0.00"), "placed", datetime.now(UTC)),
        )
        return InjectionResult(self.key, f"order_id={order_id} quantity=-5")


class DuplicateOrder(Failure):
    """Re-insert the most recent ``orders`` row as an exact duplicate.

    Corrupts the ``orders`` table by copying the latest order verbatim,
    breaking the uniqueness expectation across order attributes.
    """

    key = "duplicate_order"
    summary = "Re-insert the most recent order as an exact duplicate row."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Duplicate the latest order row, if one exists.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` with the duplicate's ``order_id``, or a
            no-op detail when the table is empty.
        """
        latest = repo.latest_order(conn)
        if latest is None:
            return InjectionResult(self.key, "no orders to duplicate")
        _, customer_id, product_id, quantity, unit_price, total_amount, status, ordered_at = latest
        order_id = repo.insert_order(
            conn,
            _order_columns(conn),
            (customer_id, product_id, quantity, unit_price, total_amount, status, ordered_at),
        )
        return InjectionResult(self.key, f"duplicated into order_id={order_id}")


class LateArrival(Failure):
    """Insert an ``orders`` row backdated 45 days (late-arriving data).

    Corrupts the freshness of the ``orders`` table by adding a delivered order
    whose ``ordered_at`` is far in the past.
    """

    key = "late_arrival"
    summary = "Insert an order backdated 45 days (late-arriving data)."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Insert one order timestamped 45 days in the past.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` reporting the ``order_id`` and backdated
            order date.
        """
        customer_id = repo.sample_customer_ids(conn, 1)[0]
        product_id, unit_price = repo.sample_products(conn, 1)[0]
        backdated = datetime.now(UTC) - timedelta(days=45)
        order_id = repo.insert_order(
            conn,
            _order_columns(conn),
            (customer_id, product_id, 1, unit_price, unit_price, "delivered", backdated),
        )
        return InjectionResult(self.key, f"order_id={order_id} ordered_at={backdated.date()}")


class VolumeSpike(Failure):
    """Insert a sudden burst of ``orders`` rows (volume anomaly).

    Corrupts the ``orders`` table's volume profile by appending many orders in a
    single batch, all sharing one timestamp.
    """

    key = "volume_spike"
    summary = "Insert a sudden burst of orders (volume anomaly)."

    def __init__(self, burst: int = 500) -> None:
        """Configure the size of the inserted burst.

        Args:
            burst: Number of orders to insert in a single batch.
        """
        self.burst = burst

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Insert ``self.burst`` orders in one batch at the current time.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` reporting how many orders were inserted.
        """
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
        return InjectionResult(self.key, f"inserted {self.burst} orders in one burst")


class SchemaDrift(Failure):
    """Rename ``orders.customer_id`` to ``user_id`` (schema drift).

    Corrupts the ``orders`` schema by renaming the customer-reference column,
    breaking any consumer that expects the original column name. Idempotent: a
    second injection detects the already-renamed column and no-ops.
    """

    key = "schema_drift"
    summary = "Rename orders.customer_id -> user_id (schema drift on the customer link)."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Rename the ``orders`` customer column to ``user_id``.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` describing the rename, or a no-op detail
            when the column has already drifted.
        """
        current = repo.order_customer_column(conn)
        if current == "user_id":
            return InjectionResult(self.key, "already drifted (column is user_id)")
        repo.execute(conn, "ALTER TABLE orders RENAME COLUMN customer_id TO user_id")
        return InjectionResult(self.key, "orders.customer_id renamed to user_id")


class OrphanPayment(Failure):
    """Insert a ``payments`` row referencing a non-existent ``order_id``.

    Corrupts referential integrity between ``payments`` and ``orders`` by
    dropping the foreign key and inserting a payment whose order does not exist.
    """

    key = "orphan_payment"
    summary = "Insert a payment referencing a non-existent order_id."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Drop the payments foreign key and insert an orphaned payment.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` naming the dangling ``order_id``.
        """
        repo.execute(conn, "ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_order_id_fkey")
        repo.execute(
            conn,
            "INSERT INTO payments (order_id, method, amount, status, paid_at) VALUES (%s, %s, %s, %s, %s)",
            (999999999, "credit_card", Decimal("10.00"), "captured", datetime.now(UTC)),
        )
        return InjectionResult(self.key, "payment inserted for order_id=999999999")


class RecurringIncident(Failure):
    """Re-inject a negative-price order so the same defect recurs over time.

    Corrupts the ``orders`` table with another sub-zero priced order and reports
    how many times this defect has already been recorded, simulating a repeat
    offender that surfaces again and again.
    """

    key = "recurring_incident"
    summary = "Re-inject negative prices repeatedly so the same incident appears many times."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Insert another negative-price order and report its occurrence count.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` reporting the new ``order_id`` and the
            running occurrence number for this defect.
        """
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
        return InjectionResult(self.key, f"order_id={order_id} (occurrence #{seen})")


class AmbiguousAnomaly(Failure):
    """Drop revenue via cancellations AND a price cut at once (two root causes).

    Corrupts the ``orders`` and ``products`` tables simultaneously so that a
    revenue decline has two equally plausible explanations, making the root
    cause ambiguous.
    """

    key = "ambiguous_anomaly"
    summary = "Revenue drops via cancellations AND a price cut at once (two plausible root causes)."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Cancel a batch of orders and halve a sample of product prices.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` summarising both corruptions.
        """
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
        return InjectionResult(self.key, "200 orders cancelled + 20 products price-cut 50%")


class DestructiveFix(Failure):
    """Corrupt ``total_amount`` on many rows so only a bulk overwrite repairs it.

    Zeroes the order total on a wide slice of the ``orders`` table, modelling a
    defect whose remediation is necessarily destructive (a mass overwrite).
    """

    key = "destructive_fix"
    summary = "Corrupt total_amount on many rows so the only fix is a bulk overwrite."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Zero ``total_amount`` on the most recent 300 orders.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` describing the bulk corruption.
        """
        repo.execute(
            conn,
            "UPDATE orders SET total_amount = 0 WHERE order_id IN "
            "(SELECT order_id FROM orders ORDER BY order_id DESC LIMIT 300)",
        )
        return InjectionResult(self.key, "zeroed total_amount on 300 orders (bulk fix required)")


class MalformedData(Failure):
    """Write garbage free-text into ``orders.status`` on several rows.

    Corrupts the ``status`` column with control characters and markup so the
    field can no longer be parsed against its expected value domain.
    """

    key = "malformed_data"
    summary = "Inject garbage into status fields (free-text noise to summarise)."

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Overwrite ``status`` with a garbage string on 25 recent orders.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` reporting how many rows were corrupted.
        """
        garbage = "���/NULL/<script>/0x00 ¿status?"
        repo.execute(
            conn,
            "UPDATE orders SET status = %s WHERE order_id IN "
            "(SELECT order_id FROM orders ORDER BY order_id DESC LIMIT 25)",
            (garbage,),
        )
        return InjectionResult(self.key, "wrote garbage status to 25 orders")


class SlowSource(Failure):
    """Hold a lock on ``orders`` to make the source slow/unresponsive.

    Models a transient availability defect by sleeping inside a transaction,
    stalling readers of the ``orders`` table for a configurable duration.
    """

    key = "slow_source"
    summary = "Hold a lock on orders to make the source slow/unresponsive for a while."

    def __init__(self, seconds: int = 8) -> None:
        """Configure how long the source is stalled.

        Args:
            seconds: Duration of the simulated stall, in seconds.
        """
        self.seconds = seconds

    def inject(self, conn: psycopg.Connection) -> InjectionResult:
        """Stall the connection for ``self.seconds`` via ``pg_sleep``.

        Args:
            conn: An open PostgreSQL connection.

        Returns:
            An :class:`InjectionResult` reporting the stall duration.
        """
        with conn.cursor() as cur:
            cur.execute("SET lock_timeout = '1s'")
            cur.execute(f"SELECT pg_sleep({self.seconds})")
        return InjectionResult(self.key, f"source stalled for {self.seconds}s")


class MultiFailureCascade(Failure):
    """Fire schema drift, NULL customers, and a volume spike together.

    Composes several sub-defects into one mixed incident. Because it drives the
    sub-injectors itself, it also owns its ledger writes: when ``record`` is
    true it persists each sub-defect, and the caller must not record it again.
    """

    key = "multi_failure_cascade"
    summary = "Fire schema drift + nulls + a volume spike together (mixed incident)."

    def inject(self, conn: psycopg.Connection, record: bool = False) -> InjectionResult:
        """Run the sub-defects in sequence, optionally recording each.

        Args:
            conn: An open PostgreSQL connection.
            record: When true, write each sub-defect's result to the
                ``injected_incidents`` ledger. Silent by default so callers opt
                in explicitly (e.g. ``gen inject --record`` /
                ``make inject RECORD=1``).

        Returns:
            An :class:`InjectionResult` summarising the sub-defects that fired.
        """
        parts: list[str] = []
        for key in ("missing_customer", "volume_spike", "schema_drift"):
            result = REGISTRY[key].inject(conn)
            # Silent by default: only write the ground-truth ledger when the
            # operator opts in (gen inject --record / make inject RECORD=1).
            if record:
                repo.record_incident(conn, result.failure, result.detail)
            parts.append(result.failure)
        return InjectionResult(self.key, "cascade: " + ", ".join(parts))


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
    """Look up a defect injector by its registry key.

    Args:
        key: The :attr:`Failure.key` of the desired injector.

    Returns:
        The registered :class:`Failure` singleton for ``key``.

    Raises:
        KeyError: If ``key`` is not present in :data:`REGISTRY`; the message
            lists the available keys.
    """
    if key not in REGISTRY:
        available = ", ".join(sorted(REGISTRY))
        raise KeyError(f"unknown failure '{key}'. available: {available}")
    return REGISTRY[key]
