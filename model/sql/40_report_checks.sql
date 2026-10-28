-- Executed by query.sh check inside a READ ONLY transaction.
-- These checks compare the model to its current core, not fixed volumes.
DO $$
BEGIN
    IF (SELECT count(*) FROM mart.order_totals) <> (SELECT count(*) FROM core.orders)
       OR (SELECT count(DISTINCT order_id) FROM mart.order_totals) <> (SELECT count(*) FROM core.orders) THEN
        RAISE EXCEPTION 'Order view lost or multiplied orders';
    END IF;
    IF (SELECT count(*) FROM mart.sales_items) <>
       (SELECT count(*) FROM core.order_items i JOIN core.orders o USING (order_id) WHERE o.order_status = 'delivered')
       OR (SELECT count(*) FROM mart.sales_items) <>
          (SELECT count(DISTINCT (order_id, order_item_id)) FROM mart.sales_items) THEN
        RAISE EXCEPTION 'Sales view lost or multiplied delivered positions';
    END IF;
    IF EXISTS (SELECT 1 FROM mart.sales_items WHERE order_status IS DISTINCT FROM 'delivered') THEN
        RAISE EXCEPTION 'Sales view contains non-delivered positions';
    END IF;
    IF EXISTS (SELECT 1 FROM mart.order_totals WHERE order_status = 'delivered' AND (item_count = 0 OR order_amount IS NULL)) THEN
        RAISE EXCEPTION 'Delivered orders have incomplete item amounts';
    END IF;
    IF (SELECT sum(item_amount) FROM mart.sales_items) IS DISTINCT FROM
       (SELECT sum(items_amount) FROM mart.order_totals WHERE order_status = 'delivered')
       OR (SELECT sum(item_amount) FROM mart.sales_items) IS DISTINCT FROM
          (SELECT sum(i.price) FROM core.order_items i JOIN core.orders o USING (order_id) WHERE o.order_status = 'delivered') THEN
        RAISE EXCEPTION 'Revenue differs between core, item and order views';
    END IF;
    IF (SELECT sum(item_amount_with_freight) FROM mart.sales_items) IS DISTINCT FROM
       (SELECT sum(order_amount) FROM mart.order_totals WHERE order_status = 'delivered') THEN
        RAISE EXCEPTION 'Order amounts with freight differ between views';
    END IF;
    IF EXISTS (SELECT 1 FROM mart.sales_items WHERE category_key IS NULL OR category_label IS NULL) THEN
        RAISE EXCEPTION 'Sales view contains an unlabelled category';
    END IF;
    RAISE NOTICE 'PASS: report grain, preserved orders/items and matching amounts';
END $$;
