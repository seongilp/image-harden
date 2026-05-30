-- variant(naive/wolfi) x 심각도별 취약점 개수
select
    variant,
    severity,
    count(*) as findings
from {{ ref('stg_vuln_findings') }}
group by 1, 2
order by
    variant,
    case severity
        when 'CRITICAL' then 1
        when 'HIGH' then 2
        when 'MEDIUM' then 3
        when 'LOW' then 4
        else 5
    end
