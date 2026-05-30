-- 팀메이트 H2H: 같은 시즌·같은 팀에서 누가 팀 내 1위였나 (윈도우 함수)
-- 시즌별로 각 팀의 드라이버를 포인트순 랭킹 → team_rank=1이면 팀 리더
with ranked as (
    select
        season,
        constructor,
        driver_name,
        points,
        count(*)     over (partition by season, constructor)                          as team_drivers,
        row_number() over (partition by season, constructor order by points desc, position asc) as team_rank
    from {{ ref('stg_driver_standings') }}
)

select
    driver_name,
    count(*) filter (where team_rank = 1) as seasons_led_team,
    count(*) filter (where team_rank > 1) as seasons_beaten_by_teammate,
    count(*)                              as seasons_with_teammate
from ranked
where team_drivers >= 2          -- 팀메이트가 있었던 경우만
group by 1
having count(*) >= 2             -- 최소 2시즌 이상
order by seasons_led_team desc, seasons_beaten_by_teammate asc
