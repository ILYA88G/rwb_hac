-- sales_items already contains delivered orders only; revenue excludes freight.
SELECT seller_id, seller_city, seller_state,
       count(DISTINCT order_id) AS order_count,
       sum(quantity) AS units_sold,
       sum(item_amount) AS revenue
FROM mart.sales_items
GROUP BY seller_id, seller_city, seller_state
ORDER BY revenue DESC, seller_id
LIMIT 10;
