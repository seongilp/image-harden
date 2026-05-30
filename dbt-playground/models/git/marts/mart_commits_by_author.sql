-- 작성자별 커밋 수 + 활동 기간
select
    author,
    count(*)         as commits,
    min(commit_date) as first_commit,
    max(commit_date) as last_commit
from {{ ref('stg_commits') }}
group by 1
order by commits desc
