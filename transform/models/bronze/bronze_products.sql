select
    product_id,
    sku,
    name,
    category,
    unit_price,
    cost,
    created_at,
    _ingested_at,
    _source_watermark

from {{ source('raw', 'raw_products') }}
