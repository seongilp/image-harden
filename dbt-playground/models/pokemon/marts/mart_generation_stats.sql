-- 세대별 포켓몬 수 + 평균 종족값 + 전설 수 (세대 인플레 확인)
select
    generation,
    count(*)                             as pokemon,
    round(avg(total), 1)                 as avg_total,
    count(*) filter (where is_legendary) as legendaries
from {{ ref('stg_pokemon') }}
group by 1
order by generation
