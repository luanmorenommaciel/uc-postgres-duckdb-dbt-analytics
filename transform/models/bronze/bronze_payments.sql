select
    payment_id,
    order_id,
    method,
    amount,
    trim(status) as status,
    paid_at,
    _ingested_at,
    _source_watermark

from {{ source('raw', 'raw_payments') }}
