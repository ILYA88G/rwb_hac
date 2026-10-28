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
