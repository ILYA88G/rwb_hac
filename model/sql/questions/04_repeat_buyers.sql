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
