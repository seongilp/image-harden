-- conventional commit 타입별 커밋 수 (feat/docs/refactor/...)
select
    commit_type,
    count(*) as commits
from {{ ref('stg_commits') }}
group by 1
order by commits desc
