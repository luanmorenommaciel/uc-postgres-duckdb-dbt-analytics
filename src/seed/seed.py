from __future__ import annotations

import argparse
import sys

from faker import Faker

from src.db.connection import connect, count, insert_returning_ids, truncate_all

from .factories import EcommerceFactory, Order


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="seed",
        description="Generate clean, correlated e-commerce data into the source PostgreSQL database.",
    )
    parser.add_argument("--customers", type=int, default=500)
    parser.add_argument("--products", type=int, default=200)
    parser.add_argument("--orders", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--truncate", action="store_true")
    return parser.parse_args(argv)


def run(customers: int, products: int, orders: int, seed: int, truncate: bool) -> dict[str, int]:
    faker = Faker()
    Faker.seed(seed)
    factory = EcommerceFactory(faker)

    with connect() as conn:
        if truncate:
            truncate_all(conn)

        customer_rows = [factory.customer() for _ in range(customers)]
        customer_ids = insert_returning_ids(
            conn,
            "customers",
            ("full_name", "email", "country", "city", "segment", "created_at"),
            [(c.full_name, c.email, c.country, c.city, c.segment, c.created_at) for c in customer_rows],
        )

        product_rows = [factory.product() for _ in range(products)]
        product_ids = insert_returning_ids(
            conn,
            "products",
            ("sku", "name", "category", "unit_price", "cost", "created_at"),
            [(p.sku, p.name, p.category, p.unit_price, p.cost, p.created_at) for p in product_rows],
        )
        product_catalog = list(zip(product_ids, (p.unit_price for p in product_rows), strict=True))

        order_models: list[Order] = []
        for _ in range(orders):
            idx = faker.random_int(0, customers - 1)
            customer_id = customer_ids[idx]
            product = faker.random_element(product_catalog)
            order_models.append(factory.order(customer_id, product, not_before=customer_rows[idx].created_at))

        order_ids = insert_returning_ids(
            conn,
            "orders",
            ("customer_id", "product_id", "quantity", "unit_price", "total_amount", "status", "ordered_at"),
            [
                (o.customer_id, o.product_id, o.quantity, o.unit_price, o.total_amount, o.status, o.ordered_at)
                for o in order_models
            ],
        )

        payment_rows = [
            factory.payment(order_id, order)
            for order_id, order in zip(order_ids, order_models, strict=True)
        ]
        insert_returning_ids(
            conn,
            "payments",
            ("order_id", "method", "amount", "status", "paid_at"),
            [(p.order_id, p.method, p.amount, p.status, p.paid_at) for p in payment_rows],
        )

        conn.commit()
        totals = {table: count(conn, table) for table in ("customers", "products", "orders", "payments")}

    return totals


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    totals = run(args.customers, args.products, args.orders, args.seed, args.truncate)
    width = max(len(t) for t in totals)
    for table, total in totals.items():
        print(f"  {table.ljust(width)}  {total:>10,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
