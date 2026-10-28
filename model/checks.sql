-- Read-only checks for the supplied Olist snapshot; not business constants for future data.
BEGIN READ ONLY;
DO $$
DECLARE
    got numeric;
BEGIN
    SELECT sum(items_amount) INTO got FROM mart.order_totals WHERE order_status = 'delivered';
    IF got IS DISTINCT FROM 13221498.11::numeric THEN RAISE EXCEPTION 'Revenue: %', got; END IF;
    SELECT round(avg(order_amount), 2) INTO got FROM mart.order_totals WHERE order_status = 'delivered';
    IF got IS DISTINCT FROM 159.88::numeric THEN RAISE EXCEPTION 'Average check: %', got; END IF;
    SELECT max(revenue) INTO got FROM (SELECT sum(item_amount) AS revenue FROM mart.sales_items GROUP BY seller_id) t;
    IF got IS DISTINCT FROM 226987.93::numeric THEN RAISE EXCEPTION 'Top seller: %', got; END IF;
    SELECT count(*) INTO got FROM core.customers;
    IF got <> 96096 THEN RAISE EXCEPTION 'Customer count: %', got; END IF;
    SELECT count(*) INTO got FROM (SELECT customer_unique_id FROM mart.order_totals GROUP BY 1 HAVING count(*) >= 2) t;
    IF got <> 2997 THEN RAISE EXCEPTION 'Repeat customers: %', got; END IF;
    SELECT count(DISTINCT category_key) INTO got FROM mart.sales_items;
    IF got <> 74 THEN RAISE EXCEPTION 'Category count: %', got; END IF;
    SELECT max(revenue) INTO got FROM (SELECT sum(item_amount) AS revenue FROM mart.sales_items GROUP BY category_key) t;
    IF got IS DISTINCT FROM 1233131.72::numeric THEN RAISE EXCEPTION 'Top category: %', got; END IF;
    SELECT sum(item_amount) INTO got FROM mart.sales_items WHERE category_key = '__unknown__';
    IF got IS DISTINCT FROM 170726.63::numeric THEN RAISE EXCEPTION 'Uncategorized revenue: %', got; END IF;
    SELECT count(*) INTO got FROM mart.order_totals WHERE purchase_month = date '2016-11-01';
    IF got <> 0 THEN RAISE EXCEPTION 'November 2016 is not empty'; END IF;
    SELECT count(*) INTO got FROM mart.order_totals WHERE NOT has_items;
    IF got <> 775 THEN RAISE EXCEPTION 'Orders without items were changed: %', got; END IF;
    SELECT count(*) INTO got FROM mart.order_totals WHERE order_status = 'delivered' AND NOT has_payments;
    IF got <> 1 THEN RAISE EXCEPTION 'Delivered order without payment was lost: %', got; END IF;
    SELECT count(*) INTO got FROM mart.order_totals WHERE order_status = 'delivered' AND order_delivered_customer_date IS NULL;
    IF got <> 8 THEN RAISE EXCEPTION 'Missing delivery dates were changed: %', got; END IF;
    SELECT count(*) INTO got FROM mart.order_totals WHERE review_count > 1;
    IF got <> 547 THEN RAISE EXCEPTION 'Multiple reviews were changed: %', got; END IF;
    SELECT count(*) INTO got FROM mart.order_totals WHERE is_late;
    IF got <> 6534 THEN RAISE EXCEPTION 'Calendar-date lateness: %', got; END IF;
    RAISE NOTICE 'PASS: all supplied controls and known edge cases';
END $$;

SELECT 'customers' AS entity, count(*) AS rows FROM core.customers
UNION ALL SELECT 'customer_profiles', count(*) FROM core.customer_profiles
UNION ALL SELECT 'sellers', count(*) FROM core.sellers
UNION ALL SELECT 'categories', count(*) FROM core.categories
UNION ALL SELECT 'products', count(*) FROM core.products
UNION ALL SELECT 'orders', count(*) FROM core.orders
UNION ALL SELECT 'order_items', count(*) FROM core.order_items
UNION ALL SELECT 'order_payments', count(*) FROM core.order_payments
UNION ALL SELECT 'order_reviews', count(*) FROM core.order_reviews
UNION ALL SELECT 'mart.order_totals', count(*) FROM mart.order_totals
UNION ALL SELECT 'mart.sales_items', count(*) FROM mart.sales_items
ORDER BY entity;

SELECT count(*) AS delivered_orders, sum(items_amount) AS revenue,
       round(avg(order_amount), 2) AS average_check,
       round(avg(item_count), 6) AS average_rows,
       round(avg(unit_count), 6) AS average_units
FROM mart.order_totals WHERE order_status = 'delivered';

-- Anomalies are preserved, not corrected. These counts are diagnostic.
SELECT count(*) FILTER (WHERE order_delivered_carrier_date < order_purchase_timestamp) AS sent_before_purchase,
       count(*) FILTER (WHERE order_delivered_customer_date < order_delivered_carrier_date) AS received_before_sent,
       count(*) FILTER (WHERE order_status = 'canceled' AND order_delivered_customer_date IS NOT NULL) AS canceled_with_delivery
FROM core.orders;
COMMIT;
