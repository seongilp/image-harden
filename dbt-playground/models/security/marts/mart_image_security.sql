-- 이미지별 크기 + 취약점 요약 (naive vs wolfi 비교의 핵심 마트)
with sizes as (
    select * from {{ ref('stg_image_sizes') }}
),

vulns as (
    select
        lang,
        variant,
        count(*)                                                         as total_vulns,
        count(*) filter (where severity in ('HIGH', 'CRITICAL'))         as high_crit_vulns
    from {{ ref('stg_vuln_findings') }}
    group by 1, 2
)

select
    s.lang,
    s.variant,
    s.size_mb,
    coalesce(v.total_vulns, 0)      as total_vulns,
    coalesce(v.high_crit_vulns, 0)  as high_crit_vulns
from sizes s
left join vulns v
    on s.lang = v.lang
    and s.variant = v.variant
order by s.lang, s.variant
