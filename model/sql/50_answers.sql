-- Compatibility file: the five original questions. For new reports use query.sh and sql/questions.

-- Revenue = goods only; delivered orders, grouped by purchase month.
-- Calendar preserves months without sales. September 2016-August 2018.
WITH months AS (
    SELECT generate_series(DATE '2016-09-01', DATE '2018-08-01', INTERVAL '1 month')::date AS month
), sales AS (
    SELECT purchase_month AS month,
           count(*) AS order_count,
           sum(items_amount) AS revenue
    FROM mart.order_totals
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= TIMESTAMP '2016-09-01'
      AND order_purchase_timestamp < TIMESTAMP '2018-09-01'
    GROUP BY purchase_month
)
SELECT m.month,
       COALESCE(s.order_count, 0) AS order_count,
       COALESCE(s.revenue, 0) AS revenue
FROM months m LEFT JOIN sales s USING (month)
ORDER BY m.month;


-- sales_items already contains delivered orders only; revenue excludes freight.
SELECT seller_id, seller_city, seller_state,
       count(DISTINCT order_id) AS order_count,
       sum(quantity) AS units_sold,
       sum(item_amount) AS revenue
FROM mart.sales_items
GROUP BY seller_id, seller_city, seller_state
ORDER BY revenue DESC, seller_id
LIMIT 10;


-- Average of complete delivered order amounts, including freight.
-- Source contract: each position is one unit, so these two averages coincide.
SELECT round(avg(order_amount), 2) AS average_order_amount,
       round(avg(item_count), 6) AS average_lines_per_order,
       round(avg(unit_count), 6) AS average_units_per_order
FROM mart.order_totals
WHERE order_status = 'delivered';


-- Stable customer identity; all order statuses, matching task controls.
-- This is repeat ordering, not a count of repeat successful deliveries.
WITH buyer_orders AS (
    SELECT customer_unique_id, count(*) AS order_count
    FROM mart.order_totals
    GROUP BY customer_unique_id
)
SELECT count(*) AS buyer_count,
       count(*) FILTER (WHERE order_count >= 2) AS repeat_buyer_count,
       round(100.0 * count(*) FILTER (WHERE order_count >= 2)
             / NULLIF(count(*), 0), 2) AS repeat_buyer_percent
FROM buyer_orders;


-- Keep __unknown__ and categories without translation.
-- Group by stable category key as well as display label.
WITH category_sales AS (
    SELECT category_key, category_label, sum(item_amount) AS revenue
    FROM mart.sales_items
    GROUP BY category_key, category_label
)
SELECT category_key, category_label, revenue,
       round(100.0 * revenue / NULLIF(sum(revenue) OVER (), 0), 2) AS revenue_percent
FROM category_sales
ORDER BY revenue DESC, category_key;
