-- Запускается внутри транзакции, открываемой run_profile.sh.
-- PostgreSQL запретит изменение постоянных таблиц.
SET TRANSACTION READ ONLY;

-- 1. Проверяем объёмы всех исходных таблиц.
SELECT 'orders' AS table_name, count(*) AS row_count
FROM raw.orders
UNION ALL
SELECT 'order_items', count(*) FROM raw.order_items
UNION ALL
SELECT 'order_payments', count(*) FROM raw.order_payments
UNION ALL
SELECT 'order_reviews', count(*) FROM raw.order_reviews
UNION ALL
SELECT 'products', count(*) FROM raw.products
UNION ALL
SELECT 'sellers', count(*) FROM raw.sellers
UNION ALL
SELECT 'customers', count(*) FROM raw.customers
UNION ALL
SELECT 'product_category_translation', count(*)
FROM raw.product_category_translation
ORDER BY table_name;

-- 2. Смотрим, на каких стадиях находятся заказы.
SELECT order_status, count(*) AS order_count
FROM raw.orders
GROUP BY order_status
ORDER BY order_count DESC;

-- 3. Отличаем запись покупателя от самого человека.
WITH buyer_counts AS (
    SELECT customer_unique_id, count(*) AS profile_count
    FROM raw.customers
    GROUP BY customer_unique_id
)
SELECT
    count(*) AS buyers,
    count(*) FILTER (WHERE profile_count > 1) AS repeat_buyers,
    round(
        100.0 * count(*) FILTER (WHERE profile_count > 1)
        / NULLIF(count(*), 0),
        2
    ) AS repeat_percent
FROM buyer_counts;

-- 4. Проверяем составной ключ позиций.
-- Ожидается ноль строк.
SELECT order_id, order_item_id, count(*) AS copies
FROM raw.order_items
GROUP BY order_id, order_item_id
HAVING count(*) > 1;

-- 5. Проверяем составной ключ платежей.
-- Ожидается ноль строк.
SELECT order_id, payment_sequential, count(*) AS copies
FROM raw.order_payments
GROUP BY order_id, payment_sequential
HAVING count(*) > 1;

-- 6. Проверяем составной ключ отзывов.
-- Ожидается ноль строк.
SELECT order_id, review_id, count(*) AS copies
FROM raw.order_reviews
GROUP BY order_id, review_id
HAVING count(*) > 1;

-- 7. Считаем товары без категории.
SELECT count(*) AS products_without_category
FROM raw.products
WHERE NULLIF(btrim(product_category_name), '') IS NULL;

-- 8. Находим категории без перевода.
SELECT DISTINCT p.product_category_name
FROM raw.products AS p
LEFT JOIN raw.product_category_translation AS t
    ON t.product_category_name = p.product_category_name
WHERE NULLIF(btrim(p.product_category_name), '') IS NOT NULL
  AND t.product_category_name IS NULL
ORDER BY p.product_category_name;
