-- 시즌별 우승 컨스트럭터 + 그 시즌 전체 포인트에서 차지한 비중(지배력)
with season_totals as (
    select
        season,
        sum(points) as season_total_points
    from {{ ref('stg_constructor_standings') }}
    group by 1
)

select
    c.season,
    c.constructor_name                                       as champion,
    c.points,
    c.wins,
    round(100.0 * c.points / nullif(t.season_total_points, 0), 1) as points_share_pct
from {{ ref('stg_constructor_standings') }} c
join season_totals t
    on c.season = t.season
where c.position = 1
order by c.season
