-- 픽업 시간대별 운행 수 + 평균 거리/요금
select
    pickup_hour,
    count(*)                    as trips,
    round(avg(trip_distance), 2) as avg_distance_mi,
    round(avg(fare_amount), 2)   as avg_fare_usd,
    round(avg(total_amount), 2)  as avg_total_usd
from {{ ref('stg_taxi') }}
group by 1
order by 1
