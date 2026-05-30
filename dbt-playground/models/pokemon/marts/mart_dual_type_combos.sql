-- 듀얼타입(Type 1 + Type 2) 조합 빈도 + 평균 종족값
select
    type1,
    type2,
    count(*)             as pokemon,
    round(avg(total), 1) as avg_total
from {{ ref('stg_pokemon') }}
where type2 is not null
group by 1, 2
order by pokemon desc, avg_total desc
