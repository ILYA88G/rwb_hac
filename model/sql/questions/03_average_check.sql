-- Average of complete delivered order amounts, including freight.
-- Source contract: each position is one unit, so these two averages coincide.
SELECT round(avg(order_amount), 2) AS average_order_amount,
       round(avg(item_count), 6) AS average_lines_per_order,
       round(avg(unit_count), 6) AS average_units_per_order
FROM mart.order_totals
WHERE order_status = 'delivered';
