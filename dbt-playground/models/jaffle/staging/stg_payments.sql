select
    id as payment_id,
    order_id,
    payment_method,
    amount / 100.0 as amount_usd   -- 원본은 센트 단위
from read_csv_auto('https://raw.githubusercontent.com/dbt-labs/jaffle_shop/main/seeds/raw_payments.csv')
