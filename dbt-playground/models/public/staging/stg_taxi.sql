-- NYC 옐로우 택시 2024-01 parquet을 원격 URL에서 직접 읽기 (httpfs + parquet pushdown)
-- 200k행만 가져와 테이블로 고정 (playground라 가볍게)
select
    tpep_pickup_datetime              as pickup_at,
    passenger_count,
    trip_distance,
    fare_amount,
    total_amount,
    extract('hour' from tpep_pickup_datetime) as pickup_hour
from read_parquet('https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2024-01.parquet')
where fare_amount > 0
  and trip_distance > 0
  and trip_distance < 100
limit 200000
