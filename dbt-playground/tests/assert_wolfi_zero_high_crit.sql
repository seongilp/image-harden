-- wolfi 하드닝 이미지는 HIGH/CRITICAL 취약점이 0이어야 한다.
-- (이 쿼리가 1행이라도 반환하면 dbt test 실패 = 하드닝 깨짐)
select
    lang,
    variant,
    high_crit_vulns
from {{ ref('mart_image_security') }}
where variant = 'wolfi'
  and high_crit_vulns > 0
