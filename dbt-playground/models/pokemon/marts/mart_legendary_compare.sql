-- 전설 vs 일반 포켓몬 평균 스탯 비교 (평균 컬럼은 avg_stats 매크로로 생성)
select
    is_legendary,
    count(*) as pokemon,
    {{ avg_stats() }}
from {{ ref('stg_pokemon') }}
group by 1
order by is_legendary desc
