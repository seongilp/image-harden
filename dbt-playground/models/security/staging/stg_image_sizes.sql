-- 이미지 크기 (seed)
select
    lang,
    variant,
    size_mb
from {{ ref('image_sizes') }}
