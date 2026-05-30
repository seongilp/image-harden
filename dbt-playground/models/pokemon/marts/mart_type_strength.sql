-- 주 타입(Type 1)별 평균 종족값 랭킹 (평균 컬럼은 avg_stats 매크로로 생성)
select
    type1,
    count(*) as pokemon,
    {{ avg_stats(include_spatk=true) }}
from {{ ref('stg_pokemon') }}
group by 1
order by avg_total desc
