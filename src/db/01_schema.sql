CREATE TABLE IF NOT EXISTS customers (
    customer_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     TEXT        NOT NULL,
    email         TEXT        NOT NULL UNIQUE,
    country       TEXT        NOT NULL,
    city          TEXT        NOT NULL,
    segment       TEXT        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS products (
    product_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku           TEXT        NOT NULL UNIQUE,
    name          TEXT        NOT NULL,
    category      TEXT        NOT NULL,
    unit_price    NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    cost          NUMERIC(10, 2) NOT NULL CHECK (cost >= 0),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
    order_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   BIGINT      NOT NULL REFERENCES customers (customer_id),
    product_id    BIGINT      NOT NULL REFERENCES products (product_id),
    quantity      INTEGER     NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    total_amount  NUMERIC(12, 2) NOT NULL CHECK (total_amount >= 0),
    status        TEXT        NOT NULL,
    ordered_at    TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS payments (
    payment_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      BIGINT      NOT NULL REFERENCES orders (order_id),
    method        TEXT        NOT NULL,
    amount        NUMERIC(12, 2) NOT NULL CHECK (amount >= 0),
    status        TEXT        NOT NULL,
    paid_at       TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_product_id  ON orders (product_id);
CREATE INDEX IF NOT EXISTS idx_orders_ordered_at  ON orders (ordered_at);
CREATE INDEX IF NOT EXISTS idx_payments_order_id  ON payments (order_id);

CREATE TABLE IF NOT EXISTS injected_incidents (
    incident_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    failure_key   TEXT        NOT NULL,
    detail        TEXT        NOT NULL,
    detected_by   TEXT        NOT NULL,
    injected_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_incidents_failure_key ON injected_incidents (failure_key);
CREATE INDEX IF NOT EXISTS idx_incidents_injected_at ON injected_incidents (injected_at);
