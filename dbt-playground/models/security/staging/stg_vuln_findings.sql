-- trivy 취약점 findings (seed) 정리
select
    lang,
    variant,
    target,
    vuln_id,
    pkg_name,
    nullif(installed_version, '') as installed_version,
    nullif(fixed_version, '')     as fixed_version,
    upper(severity)               as severity
from {{ ref('vuln_findings') }}
