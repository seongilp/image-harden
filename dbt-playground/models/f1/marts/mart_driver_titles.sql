-- 시즌별 드라이버 챔피언 (position = 1)
select
    season,
    driver_name,
    constructor,
    points,
    wins
from {{ ref('stg_driver_standings') }}
where position = 1
order by season
