select
    id as order_id,
    user_id as customer_id,
    cast(order_date as date) as order_date,
    status
from read_csv_auto('https://raw.githubusercontent.com/dbt-labs/jaffle_shop/main/seeds/raw_orders.csv')
