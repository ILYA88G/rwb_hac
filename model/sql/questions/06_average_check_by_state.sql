-- Example of a new expert question: average order amount by customer state.
-- Grain: order. All available dates. Delivered orders; freight included.
SELECT
    customer_state,
    count(*) AS order_count,
    round(avg(order_amount), 2) AS average_check
FROM mart.order_totals
WHERE order_status = 'delivered'
GROUP BY customer_state
ORDER BY average_check DESC, customer_state;
