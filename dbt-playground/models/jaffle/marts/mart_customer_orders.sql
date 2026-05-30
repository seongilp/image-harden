-- 고객별 주문 수 + 총 결제액 (jaffle_shop 정석 마트)
with customers as (
    select * from {{ ref('stg_customers') }}
),

orders as (
    select * from {{ ref('stg_orders') }}
),

order_amounts as (
    select
        order_id,
        sum(amount_usd) as order_amount
    from {{ ref('stg_payments') }}
    group by 1
)

select
    c.customer_id,
    c.first_name,
    c.last_name,
    count(o.order_id)              as number_of_orders,
    coalesce(sum(oa.order_amount), 0) as total_spent
from customers c
left join orders o
    on c.customer_id = o.customer_id
left join order_amounts oa
    on o.order_id = oa.order_id
group by 1, 2, 3
order by total_spent desc
