-- 드라이버 커리어 누적 (2010~2024 구간): 통산 포인트/승수/타이틀
select
    driver_id,
    max(driver_name)                       as driver_name,
    count(distinct season)                 as seasons,
    sum(points)                            as career_points,
    sum(wins)                              as career_wins,
    count(*) filter (where position = 1)   as titles
from {{ ref('stg_driver_standings') }}
group by 1
order by career_points desc
