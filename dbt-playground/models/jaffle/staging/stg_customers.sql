-- dbt-labs jaffle_shop 원시 CSV을 URL에서 직접 읽기 (httpfs)
select
    id as customer_id,
    first_name,
    last_name
from read_csv_auto('https://raw.githubusercontent.com/dbt-labs/jaffle_shop/main/seeds/raw_customers.csv')
