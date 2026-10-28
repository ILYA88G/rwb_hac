CREATE SCHEMA IF NOT EXISTS mart;

-- Одна строка = одна единица товара в заказе.
-- Сохраняем все статусы: фильтр зависит от конкретного отчёта.
CREATE OR REPLACE VIEW mart.item_sales AS
SELECT
    i.order_id,
    i.order_item_id,
    o.order_status,
    o.order_purchase_timestamp,
    cp.customer_unique_id,

    i.product_id,
    p.category_key,
    CASE
        WHEN p.category_key = '__unknown__' THEN 'Без категории'
        ELSE COALESCE(c.category_name_english, p.category_key)
    END AS category_name,

    i.seller_id,
    s.seller_city,
    s.seller_state,

    i.shipping_limit_date,
    i.price AS goods_amount,
    i.freight_value AS freight_amount,
    i.price + i.freight_value AS total_amount,
    1 AS quantity

FROM core.order_items AS i
JOIN core.orders AS o
    ON o.order_id = i.order_id
JOIN core.customer_profiles AS cp
    ON cp.customer_id = o.customer_id
JOIN core.products AS p
    ON p.product_id = i.product_id
JOIN core.categories AS c
    ON c.category_key = p.category_key
JOIN core.sellers AS s
    ON s.seller_id = i.seller_id;


-- Одна строка = один заказ.
-- Позиции и платежи сначала агрегируем независимо.
-- Только после этого соединяем с заказами.
CREATE OR REPLACE VIEW mart.order_summary AS
WITH item_totals AS (
    SELECT
        order_id,
        count(*) AS item_count,
        sum(price) AS goods_amount,
        sum(freight_value) AS freight_amount,
        sum(price + freight_value) AS order_amount
    FROM core.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        count(*) AS payment_count,
        sum(payment_value) AS payment_amount
    FROM core.order_payments
    GROUP BY order_id
)
SELECT
    o.order_id,
    cp.customer_unique_id,
    cp.customer_city,
    cp.customer_state,

    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    COALESCE(i.item_count, 0) AS item_count,
    i.goods_amount,
    i.freight_amount,
    i.order_amount,

    COALESCE(p.payment_count, 0) AS payment_count,
    p.payment_amount

FROM core.orders AS o
JOIN core.customer_profiles AS cp
    ON cp.customer_id = o.customer_id
LEFT JOIN item_totals AS i
    ON i.order_id = o.order_id
LEFT JOIN payment_totals AS p
    ON p.order_id = o.order_id;
