-- F1 시즌별 드라이버 최종 순위 (seed)
select
    season,
    position,
    driver_id,
    driver_name,
    code,
    constructor,
    points,
    wins
from {{ ref('f1_driver_standings') }}
