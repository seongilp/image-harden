-- 각 시즌의 드라이버 챔피언은 정확히 1명이어야 한다.
-- (이 쿼리가 행을 반환하면 = position=1이 중복/누락된 시즌이 있음 → 테스트 실패)
select
    season,
    count(*) as champions
from {{ ref('mart_driver_titles') }}
group by season
having count(*) <> 1
