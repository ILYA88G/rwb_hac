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
