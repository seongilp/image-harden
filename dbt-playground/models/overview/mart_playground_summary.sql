-- 크로스도메인 대시보드: 6개 도메인의 핵심 지표를 한 테이블로 union
-- (도메인 간 자연스러운 조인 키는 없으므로, 각 도메인 마트에서 헤드라인 숫자를 뽑아 합친다)
select 'security' as domain, 'naive 이미지 HIGH/CRIT 합계' as metric,
    cast((select sum(high_crit_vulns) from {{ ref('mart_image_security') }} where variant = 'naive') as varchar) as value
union all
select 'security', 'wolfi 이미지 HIGH/CRIT 합계',
    cast((select sum(high_crit_vulns) from {{ ref('mart_image_security') }} where variant = 'wolfi') as varchar)
union all
select 'git', '총 커밋 수',
    cast((select sum(commits) from {{ ref('mart_commits_by_type') }}) as varchar)
union all
select 'jaffle', '고객 수',
    cast((select count(*) from {{ ref('mart_customer_orders') }}) as varchar)
union all
select 'public', '택시 평균 요금($)',
    cast((select round(avg(avg_fare_usd), 2) from {{ ref('mart_taxi_by_hour') }}) as varchar)
union all
select 'f1', '통산 1위 드라이버 (2010~2024)',
    (select driver_name from {{ ref('mart_driver_career') }} order by career_points desc limit 1)
union all
select 'pokemon', '최강 주 타입 (평균 종족값)',
    (select type1 from {{ ref('mart_type_strength') }} order by avg_total desc limit 1)
