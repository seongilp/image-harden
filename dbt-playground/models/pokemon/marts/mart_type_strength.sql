-- 주 타입(Type 1)별 평균 종족값 랭킹
select
    type1,
    count(*)                as pokemon,
    round(avg(total), 1)    as avg_total,
    round(avg(attack), 1)   as avg_attack,
    round(avg(defense), 1)  as avg_defense,
    round(avg(speed), 1)    as avg_speed
from {{ ref('stg_pokemon') }}
group by 1
order by avg_total desc
