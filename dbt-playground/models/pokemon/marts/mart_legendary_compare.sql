-- 전설 vs 일반 포켓몬 평균 스탯 비교
select
    is_legendary,
    count(*)               as pokemon,
    round(avg(total), 1)   as avg_total,
    round(avg(attack), 1)  as avg_attack,
    round(avg(defense), 1) as avg_defense,
    round(avg(speed), 1)   as avg_speed
from {{ ref('stg_pokemon') }}
group by 1
order by is_legendary desc
