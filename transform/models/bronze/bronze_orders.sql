select
    order_id,
    customer_id,
    product_id,
    quantity,
    unit_price,
    total_amount,
    trim(status) as status,
    ordered_at,
    _ingested_at,
    _source_watermark,
    _schema_drift

from {{ source('raw', 'raw_orders') }}
