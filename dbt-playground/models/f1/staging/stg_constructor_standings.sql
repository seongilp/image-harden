-- F1 시즌별 컨스트럭터(팀) 최종 순위 (seed)
select
    season,
    position,
    constructor_id,
    constructor_name,
    points,
    wins
from {{ ref('f1_constructor_standings') }}
