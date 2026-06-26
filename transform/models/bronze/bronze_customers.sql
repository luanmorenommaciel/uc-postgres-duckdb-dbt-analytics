select
    customer_id,
    full_name,
    lower(email) as email,
    country,
    city,
    segment,
    created_at,
    _ingested_at,
    _source_watermark

from {{ source('raw', 'raw_customers') }}
