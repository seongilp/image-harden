-- git 커밋 로그 (seed) 정리
select
    sha,
    author,
    cast(commit_date as date) as commit_date,
    lower(commit_type)        as commit_type,
    subject
from {{ ref('git_commits') }}
