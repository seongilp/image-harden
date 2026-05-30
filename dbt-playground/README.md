# dbt-playground — dbt + DuckDB 놀이터

창고(Snowflake/BigQuery) 없이 노트북에서 dbt를 갖고 노는 프로젝트.
하나의 dbt 프로젝트에 **4개 도메인**을 넣었다. DuckDB 어댑터(`dbt-duckdb`) 하나면 끝.

## 4개 도메인

| 도메인 | 데이터 출처 | 무엇을 배우나 |
|---|---|---|
| **① security** | 이 레포 `harden-*` 이미지의 trivy 스캔 (seed) | seed → staging → mart, 커스텀 데이터 테스트로 "wolfi=CVE 0" 증명 |
| **② git** | image-harden 레포 `git log` (seed) | conventional commit 타입/작성자 집계 |
| **③ jaffle** | dbt-labs jaffle_shop 원시 CSV (원격 URL) | dbt 정석 staging→mart 조인, httpfs로 URL 직접 읽기 |
| **④ public** | NYC 옐로우 택시 2024-01 parquet (원격 URL, 20만행) | DuckDB가 원격 parquet 스트리밍 + pushdown |

## 실측 결과 (하이라이트)

```
① 이미지 크기 + 취약점          ④ NYC 택시 시간대별
 lang   variant size  hi/crit    hour trips avg_mi avg_fare
 go     naive   330MB    85       0    7403  4.00   $21.8
 go     wolfi   2.5MB     0       12  12260  3.61   $19.6
 python naive   406MB   187       18  13848  3.60   $19.2
 python wolfi    24MB     0       23   3214  6.81   $29.9
 java   naive   431MB     8
 java   wolfi    76MB     0    ② git: feat 13 · docs 7 · refactor 1
```

dbt 테스트 35개 전부 PASS. 특히 `tests/assert_wolfi_zero_high_crit.sql`이
wolfi 이미지의 HIGH/CRITICAL이 0임을 **dbt test로 증명**한다.

## 실행법

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install dbt-duckdb

python3 scripts/gen_seeds.py        # trivy/docker/git → seed CSV 생성 (① ② 갱신용)
dbt build --profiles-dir .          # seed → 모델 → 테스트 전체
dbt docs generate --profiles-dir .  # lineage 그래프 데이터
dbt docs serve --profiles-dir .     # 브라우저로 lineage/문서 보기 (인터랙티브)

# 결과 조회 (duckdb CLI)
duckdb playground.duckdb -c "select * from main_security.mart_image_security;"
```

## 구조

```
models/
├── security/  staging(stg_vuln_findings, stg_image_sizes) → marts(mart_image_security, mart_severity_breakdown)
├── git/       staging(stg_commits)                        → marts(mart_commits_by_type, mart_commits_by_author)
├── jaffle/    staging(stg_customers, stg_orders, stg_payments) → marts(mart_customer_orders)
└── public/    staging(stg_taxi)                           → marts(mart_taxi_by_hour)
seeds/         vuln_findings.csv · image_sizes.csv · git_commits.csv
tests/         assert_wolfi_zero_high_crit.sql  (커스텀 데이터 테스트)
scripts/       gen_seeds.py  (① ② seed 생성)
```

## 더 놀거리
- `dbt docs serve`로 lineage 그래프 클릭해보기
- `dbt build --select security` 처럼 도메인만 선택 실행
- 증분(incremental) 모델·스냅샷(SCD)·exposures 추가
- ④ public을 다른 공개 parquet(F1, GitHub archive 등)으로 교체
