{# 이미지 보안 상태(크기·취약점)의 '이력'을 추적하는 SCD Type 2 스냅샷.
   high_crit_vulns 또는 size_mb가 바뀔 때마다 새 버전 행을 쌓고
   dbt_valid_from / dbt_valid_to 로 언제부터 언제까지 유효했는지 기록한다.
   (실무에선 daily rebuild + 이 스냅샷으로 "CVE 추이 이력"을 만든다) #}
{% snapshot snap_image_security %}
{{
  config(
    target_schema='snapshots',
    unique_key='image_id',
    strategy='check',
    check_cols=['high_crit_vulns', 'size_mb']
  )
}}
select
    lang || '-' || variant as image_id,
    lang,
    variant,
    size_mb,
    high_crit_vulns
from {{ ref('mart_image_security') }}
{% endsnapshot %}
