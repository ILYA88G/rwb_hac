-- Capibara model v1. PostgreSQL 16. Input: existing raw; output: core + mart.
-- Run with psql -v ON_ERROR_STOP=1. Entire refresh is atomic.
-- raw is SELECT/LOCK only. No source files or source tables are modified.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';
SET LOCAL DateStyle = 'ISO, YMD';

DO $$
BEGIN
    IF NOT pg_try_advisory_xact_lock(74281, 1) THEN
        RAISE EXCEPTION 'Another Capibara model build is running';
    END IF;
END $$;

LOCK TABLE raw.customers, raw.sellers, raw.products,
    raw.product_category_translation, raw.orders, raw.order_items,
    raw.order_payments, raw.order_reviews IN SHARE MODE;

-- Reject conversions that would silently change the source meaning.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM raw.orders) THEN
        RAISE EXCEPTION 'raw.orders is empty; this script never loads or rewrites raw';
    END IF;
    IF EXISTS (
        SELECT 1 FROM raw.products
        WHERE btrim(product_category_name) = '__unknown__'
    ) THEN
        RAISE EXCEPTION 'Reserved category key __unknown__ exists in the source';
    END IF;
    IF EXISTS (
        SELECT 1 FROM raw.product_category_translation
        GROUP BY nullif(btrim(product_category_name), '') HAVING count(*) > 1
    ) OR EXISTS (
        SELECT 1 FROM raw.product_category_translation
        WHERE nullif(btrim(product_category_name), '') IS NULL
    ) THEN
        RAISE EXCEPTION 'Category translation keys are missing or duplicated';
    END IF;
    IF EXISTS (
        SELECT 1 FROM raw.orders
        WHERE nullif(btrim(order_estimated_delivery_date), '')::timestamp::time <> time '00:00:00'
    ) THEN
        RAISE EXCEPTION 'Estimated delivery contains a time; review the date-only contract';
    END IF;
    IF EXISTS (
        SELECT 1 FROM (
            SELECT nullif(btrim(price), '')::numeric AS amount FROM raw.order_items
            UNION ALL
            SELECT nullif(btrim(freight_value), '')::numeric FROM raw.order_items
            UNION ALL
            SELECT nullif(btrim(payment_value), '')::numeric FROM raw.order_payments
        ) amounts WHERE amount <> round(amount, 2)
    ) THEN
        RAISE EXCEPTION 'A monetary value has more than two meaningful decimal places';
    END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS core;

-- One stable customer identity, without an arbitrary current address.
CREATE TABLE IF NOT EXISTS core.customers (
    customer_unique_id text PRIMARY KEY
);

-- One source customer record, preserving the address associated with it.
CREATE TABLE IF NOT EXISTS core.customer_profiles (
    customer_id text PRIMARY KEY,
    customer_unique_id text NOT NULL REFERENCES core.customers(customer_unique_id),
    customer_zip_code_prefix text,
    customer_city text,
    customer_state text
);

CREATE TABLE IF NOT EXISTS core.sellers (
    seller_id text PRIMARY KEY,
    seller_zip_code_prefix text,
    seller_city text,
    seller_state text
);

-- category_key = original Portuguese name, or '__unknown__' for no category.
-- Build the set of keys from products, then LEFT JOIN the translation source.
CREATE TABLE IF NOT EXISTS core.categories (
    category_key text PRIMARY KEY,
    category_name_english text
);

CREATE TABLE IF NOT EXISTS core.products (
    product_id text PRIMARY KEY,
    category_key text NOT NULL REFERENCES core.categories(category_key),
    product_name_length integer,
    product_description_length integer,
    product_photos_qty integer,
    product_weight_g integer,
    product_length_cm integer,
    product_height_cm integer,
    product_width_cm integer
);

CREATE TABLE IF NOT EXISTS core.orders (
    order_id text PRIMARY KEY,
    customer_id text NOT NULL REFERENCES core.customer_profiles(customer_id),
    order_status text NOT NULL,
    order_purchase_timestamp timestamp without time zone NOT NULL,
    order_approved_at timestamp without time zone,
    order_delivered_carrier_date timestamp without time zone,
    order_delivered_customer_date timestamp without time zone,
    order_estimated_delivery_date date NOT NULL
);

-- Each source row is ONE unit. order_item_id is a sequence number, not quantity.
CREATE TABLE IF NOT EXISTS core.order_items (
    order_id text NOT NULL REFERENCES core.orders(order_id),
    order_item_id integer NOT NULL CHECK (order_item_id > 0),
    product_id text NOT NULL REFERENCES core.products(product_id),
    seller_id text NOT NULL REFERENCES core.sellers(seller_id),
    shipping_limit_date timestamp without time zone NOT NULL,
    price numeric(14,2) NOT NULL CHECK (price >= 0),
    freight_value numeric(14,2) NOT NULL CHECK (freight_value >= 0),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE IF NOT EXISTS core.order_payments (
    order_id text NOT NULL REFERENCES core.orders(order_id),
    payment_sequential integer NOT NULL CHECK (payment_sequential > 0),
    payment_type text NOT NULL,
    payment_installments integer NOT NULL CHECK (payment_installments >= 0),
    payment_value numeric(14,2) NOT NULL CHECK (payment_value >= 0),
    PRIMARY KEY (order_id, payment_sequential)
);

-- review_id alone is not unique in this snapshot. The pair below is unique.
-- Preserve all reviews; selection of one review belongs to a report view.
CREATE TABLE IF NOT EXISTS core.order_reviews (
    order_id text NOT NULL REFERENCES core.orders(order_id),
    review_id text NOT NULL,
    review_score smallint NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_comment_title text,
    review_comment_message text,
    review_creation_date timestamp without time zone NOT NULL,
    review_answer_timestamp timestamp without time zone NOT NULL,
    PRIMARY KEY (order_id, review_id)
);

-- Fail on a changed contract BEFORE replacing any existing model rows.
-- The expected schema below is checked against actual names, types and nullability.
DO $$
BEGIN
    IF EXISTS (
        WITH expected(table_name, column_name, data_type, required, position) AS (VALUES
        ('customers', 'customer_unique_id', 'text', true, 1),
        ('customer_profiles', 'customer_id', 'text', true, 1),
        ('customer_profiles', 'customer_unique_id', 'text', true, 2),
        ('customer_profiles', 'customer_zip_code_prefix', 'text', false, 3),
        ('customer_profiles', 'customer_city', 'text', false, 4),
        ('customer_profiles', 'customer_state', 'text', false, 5),
        ('sellers', 'seller_id', 'text', true, 1),
        ('sellers', 'seller_zip_code_prefix', 'text', false, 2),
        ('sellers', 'seller_city', 'text', false, 3),
        ('sellers', 'seller_state', 'text', false, 4),
        ('categories', 'category_key', 'text', true, 1),
        ('categories', 'category_name_english', 'text', false, 2),
        ('products', 'product_id', 'text', true, 1),
        ('products', 'category_key', 'text', true, 2),
        ('products', 'product_name_length', 'integer', false, 3),
        ('products', 'product_description_length', 'integer', false, 4),
        ('products', 'product_photos_qty', 'integer', false, 5),
        ('products', 'product_weight_g', 'integer', false, 6),
        ('products', 'product_length_cm', 'integer', false, 7),
        ('products', 'product_height_cm', 'integer', false, 8),
        ('products', 'product_width_cm', 'integer', false, 9),
        ('orders', 'order_id', 'text', true, 1),
        ('orders', 'customer_id', 'text', true, 2),
        ('orders', 'order_status', 'text', true, 3),
        ('orders', 'order_purchase_timestamp', 'timestamp without time zone', true, 4),
        ('orders', 'order_approved_at', 'timestamp without time zone', false, 5),
        ('orders', 'order_delivered_carrier_date', 'timestamp without time zone', false, 6),
        ('orders', 'order_delivered_customer_date', 'timestamp without time zone', false, 7),
        ('orders', 'order_estimated_delivery_date', 'date', true, 8),
        ('order_items', 'order_id', 'text', true, 1),
        ('order_items', 'order_item_id', 'integer', true, 2),
        ('order_items', 'product_id', 'text', true, 3),
        ('order_items', 'seller_id', 'text', true, 4),
        ('order_items', 'shipping_limit_date', 'timestamp without time zone', true, 5),
        ('order_items', 'price', 'numeric(14,2)', true, 6),
        ('order_items', 'freight_value', 'numeric(14,2)', true, 7),
        ('order_payments', 'order_id', 'text', true, 1),
        ('order_payments', 'payment_sequential', 'integer', true, 2),
        ('order_payments', 'payment_type', 'text', true, 3),
        ('order_payments', 'payment_installments', 'integer', true, 4),
        ('order_payments', 'payment_value', 'numeric(14,2)', true, 5),
        ('order_reviews', 'order_id', 'text', true, 1),
        ('order_reviews', 'review_id', 'text', true, 2),
        ('order_reviews', 'review_score', 'smallint', true, 3),
        ('order_reviews', 'review_comment_title', 'text', false, 4),
        ('order_reviews', 'review_comment_message', 'text', false, 5),
        ('order_reviews', 'review_creation_date', 'timestamp without time zone', true, 6),
        ('order_reviews', 'review_answer_timestamp', 'timestamp without time zone', true, 7)
        ), actual AS (
            SELECT c.relname::text, a.attname::text, format_type(a.atttypid, a.atttypmod),
                   a.attnotnull, a.attnum::integer
            FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'core' AND c.relkind = 'r'
              AND c.relname IN (SELECT table_name FROM expected)
              AND a.attnum > 0 AND NOT a.attisdropped
        )
        (SELECT * FROM expected EXCEPT SELECT * FROM actual)
        UNION ALL
        (SELECT * FROM actual EXCEPT SELECT * FROM expected)
    ) THEN
        RAISE EXCEPTION 'Existing core columns differ from contract v1; nothing will be refreshed';
    END IF;
    IF EXISTS (
        WITH expected(table_name, key_columns) AS (VALUES
        ('customers', ARRAY['customer_unique_id']::text[]),
        ('customer_profiles', ARRAY['customer_id']::text[]),
        ('sellers', ARRAY['seller_id']::text[]),
        ('categories', ARRAY['category_key']::text[]),
        ('products', ARRAY['product_id']::text[]),
        ('orders', ARRAY['order_id']::text[]),
        ('order_items', ARRAY['order_id','order_item_id']::text[]),
        ('order_payments', ARRAY['order_id','payment_sequential']::text[]),
        ('order_reviews', ARRAY['order_id','review_id']::text[])
        ), actual AS (
            SELECT c.relname::text,
                   array_agg(a.attname::text ORDER BY k.position) AS key_columns
            FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            CROSS JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS k(attnum, position)
            JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.attnum
            WHERE n.nspname = 'core' AND con.contype = 'p'
              AND c.relname IN (SELECT table_name FROM expected)
            GROUP BY c.relname
        )
        SELECT * FROM expected EXCEPT SELECT * FROM actual
    ) THEN
        RAISE EXCEPTION 'Existing core primary keys differ from contract v1';
    END IF;
END $$;

-- Only these nine derived tables are refreshed. No CASCADE and no DROP.
TRUNCATE TABLE core.order_reviews, core.order_payments, core.order_items,
    core.orders, core.customer_profiles, core.products, core.categories,
    core.sellers, core.customers;

INSERT INTO core.customers (customer_unique_id)
SELECT DISTINCT nullif(btrim(customer_unique_id), '') FROM raw.customers;

INSERT INTO core.customer_profiles (
    customer_id, customer_unique_id, customer_zip_code_prefix, customer_city, customer_state
)
SELECT nullif(btrim(customer_id), ''), nullif(btrim(customer_unique_id), ''),
       nullif(btrim(customer_zip_code_prefix), ''), nullif(btrim(customer_city), ''),
       nullif(btrim(customer_state), '')
FROM raw.customers;

INSERT INTO core.sellers (seller_id, seller_zip_code_prefix, seller_city, seller_state)
SELECT nullif(btrim(seller_id), ''), nullif(btrim(seller_zip_code_prefix), ''),
       nullif(btrim(seller_city), ''), nullif(btrim(seller_state), '')
FROM raw.sellers;

INSERT INTO core.categories (category_key, category_name_english)
SELECT categories.category_key, nullif(btrim(t.product_category_name_english), '')
FROM (
    SELECT DISTINCT nullif(btrim(product_category_name), '') AS category_key
    FROM raw.products WHERE nullif(btrim(product_category_name), '') IS NOT NULL
    UNION SELECT '__unknown__'
) categories
LEFT JOIN raw.product_category_translation t
    ON nullif(btrim(t.product_category_name), '') = categories.category_key;

INSERT INTO core.products (
    product_id, category_key, product_name_length, product_description_length,
    product_photos_qty, product_weight_g, product_length_cm, product_height_cm, product_width_cm
)
SELECT nullif(btrim(product_id), ''),
       coalesce(nullif(btrim(product_category_name), ''), '__unknown__'),
       nullif(btrim(product_name_lenght), '')::integer,
       nullif(btrim(product_description_lenght), '')::integer,
       nullif(btrim(product_photos_qty), '')::integer,
       nullif(btrim(product_weight_g), '')::integer,
       nullif(btrim(product_length_cm), '')::integer,
       nullif(btrim(product_height_cm), '')::integer,
       nullif(btrim(product_width_cm), '')::integer
FROM raw.products;

INSERT INTO core.orders (
    order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at,
    order_delivered_carrier_date, order_delivered_customer_date, order_estimated_delivery_date
)
SELECT nullif(btrim(order_id), ''), nullif(btrim(customer_id), ''),
       nullif(btrim(order_status), ''),
       nullif(btrim(order_purchase_timestamp), '')::timestamp,
       nullif(btrim(order_approved_at), '')::timestamp,
       nullif(btrim(order_delivered_carrier_date), '')::timestamp,
       nullif(btrim(order_delivered_customer_date), '')::timestamp,
       nullif(btrim(order_estimated_delivery_date), '')::timestamp::date
FROM raw.orders;

INSERT INTO core.order_items (
    order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value
)
SELECT nullif(btrim(order_id), ''), nullif(btrim(order_item_id), '')::integer,
       nullif(btrim(product_id), ''), nullif(btrim(seller_id), ''),
       nullif(btrim(shipping_limit_date), '')::timestamp,
       nullif(btrim(price), '')::numeric(14,2), nullif(btrim(freight_value), '')::numeric(14,2)
FROM raw.order_items;

INSERT INTO core.order_payments (
    order_id, payment_sequential, payment_type, payment_installments, payment_value
)
SELECT nullif(btrim(order_id), ''), nullif(btrim(payment_sequential), '')::integer,
       nullif(btrim(payment_type), ''), nullif(btrim(payment_installments), '')::integer,
       nullif(btrim(payment_value), '')::numeric(14,2)
FROM raw.order_payments;

INSERT INTO core.order_reviews (
    order_id, review_id, review_score, review_comment_title, review_comment_message,
    review_creation_date, review_answer_timestamp
)
SELECT nullif(btrim(order_id), ''), nullif(btrim(review_id), ''),
       nullif(btrim(review_score), '')::smallint,
       nullif(review_comment_title, ''), nullif(review_comment_message, ''),
       nullif(btrim(review_creation_date), '')::timestamp,
       nullif(btrim(review_answer_timestamp), '')::timestamp
FROM raw.order_reviews;

ANALYZE core.customers;
ANALYZE core.customer_profiles;
ANALYZE core.sellers;
ANALYZE core.categories;
ANALYZE core.products;
ANALYZE core.orders;
ANALYZE core.order_items;
ANALYZE core.order_payments;
ANALYZE core.order_reviews;

CREATE SCHEMA IF NOT EXISTS mart;

-- Exactly one row per order, retaining ALL statuses and orders with missing facts.
CREATE OR REPLACE VIEW mart.order_totals AS
WITH item_totals AS (
    SELECT order_id,
           count(*) AS item_count,
           count(*) AS unit_count,
           count(DISTINCT product_id) AS product_count,
           count(DISTINCT seller_id) AS seller_count,
           sum(price) AS items_amount,
           sum(freight_value) AS freight_amount
    FROM core.order_items
    GROUP BY order_id
), payment_totals AS (
    SELECT order_id, count(*) AS payment_count, sum(payment_value) AS payment_amount
    FROM core.order_payments
    GROUP BY order_id
), review_totals AS (
    SELECT order_id, count(*) AS review_count
    FROM core.order_reviews
    GROUP BY order_id
), latest_review AS (
    SELECT DISTINCT ON (order_id)
           order_id, review_score, review_answer_timestamp
    FROM core.order_reviews
    ORDER BY order_id, review_answer_timestamp DESC NULLS LAST,
             review_creation_date DESC NULLS LAST, review_id DESC
)
SELECT o.order_id,
       o.customer_id,
       cp.customer_unique_id,
       cp.customer_city,
       cp.customer_state,
       o.order_status,
       o.order_purchase_timestamp,
       date_trunc('month', o.order_purchase_timestamp)::date AS purchase_month,
       o.order_approved_at,
       o.order_delivered_carrier_date,
       o.order_delivered_customer_date,
       o.order_estimated_delivery_date,
       coalesce(i.item_count, 0::bigint) AS item_count,
       coalesce(i.unit_count, 0::bigint) AS unit_count,
       coalesce(i.product_count, 0::bigint) AS product_count,
       coalesce(i.seller_count, 0::bigint) AS seller_count,
       i.items_amount,
       i.freight_amount,
       i.items_amount + i.freight_amount AS order_amount,
       coalesce(p.payment_count, 0::bigint) AS payment_count,
       p.payment_amount,
       coalesce(r.review_count, 0::bigint) AS review_count,
       lr.review_score AS latest_review_score,
       lr.review_answer_timestamp AS latest_review_answer_timestamp,
       (i.order_id IS NOT NULL) AS has_items,
       (p.order_id IS NOT NULL) AS has_payments,
       CASE
           WHEN o.order_status = 'delivered'
                AND o.order_delivered_customer_date IS NOT NULL
           THEN o.order_delivered_customer_date::date > o.order_estimated_delivery_date
           ELSE NULL
       END AS is_late
FROM core.orders o
JOIN core.customer_profiles cp ON cp.customer_id = o.customer_id
LEFT JOIN item_totals i ON i.order_id = o.order_id
LEFT JOIN payment_totals p ON p.order_id = o.order_id
LEFT JOIN review_totals r ON r.order_id = o.order_id
LEFT JOIN latest_review lr ON lr.order_id = o.order_id;

-- Exactly one row per unit of a DELIVERED order. No payments/reviews join.
-- Revenue here means merchandise amount, excluding freight and platform fees.
CREATE OR REPLACE VIEW mart.sales_items AS
SELECT i.order_id,
       i.order_item_id,
       i.product_id,
       i.seller_id,
       s.seller_city,
       s.seller_state,
       o.customer_id,
       cp.customer_unique_id,
       cp.customer_city,
       cp.customer_state,
       o.order_status,
       o.order_purchase_timestamp,
       date_trunc('month', o.order_purchase_timestamp)::date AS purchase_month,
       pr.category_key,
       cat.category_name_english,
       CASE WHEN cat.category_key = '__unknown__' THEN 'Не указана'
            ELSE coalesce(cat.category_name_english, cat.category_key)
       END AS category_label,
       1::integer AS quantity,
       i.price AS item_amount,
       i.freight_value AS freight_amount,
       i.price + i.freight_value AS item_amount_with_freight,
       i.shipping_limit_date
FROM core.order_items i
JOIN core.orders o ON o.order_id = i.order_id
JOIN core.customer_profiles cp ON cp.customer_id = o.customer_id
JOIN core.products pr ON pr.product_id = i.product_id
JOIN core.categories cat ON cat.category_key = pr.category_key
JOIN core.sellers s ON s.seller_id = i.seller_id
WHERE o.order_status = 'delivered';

-- Dynamic integrity checks: these remain valid if source volumes grow.
DO $$
DECLARE
    pair record;
    source_count bigint;
    target_count bigint;
BEGIN
    FOR pair IN SELECT * FROM (VALUES
        ('orders', 'orders'), ('order_items', 'order_items'),
        ('order_payments', 'order_payments'), ('order_reviews', 'order_reviews'),
        ('products', 'products'), ('sellers', 'sellers'), ('customers', 'customer_profiles')
    ) AS tables(source_name, target_name)
    LOOP
        EXECUTE format('SELECT count(*) FROM raw.%I', pair.source_name) INTO source_count;
        EXECUTE format('SELECT count(*) FROM core.%I', pair.target_name) INTO target_count;
        IF source_count <> target_count THEN
            RAISE EXCEPTION 'Row loss in core.%: raw %, core %', pair.target_name, source_count, target_count;
        END IF;
    END LOOP;

    IF (SELECT count(*) FROM core.customers) <>
       (SELECT count(DISTINCT nullif(btrim(customer_unique_id), '')) FROM raw.customers) THEN
        RAISE EXCEPTION 'Unique customer count mismatch';
    END IF;
    IF (SELECT count(*) FROM core.categories) <>
       (SELECT count(DISTINCT nullif(btrim(product_category_name), '')) + 1 FROM raw.products) THEN
        RAISE EXCEPTION 'Category count mismatch';
    END IF;
    IF (SELECT sum(price) FROM core.order_items) IS DISTINCT FROM
       (SELECT sum(nullif(btrim(price), '')::numeric) FROM raw.order_items)
       OR (SELECT sum(freight_value) FROM core.order_items) IS DISTINCT FROM
          (SELECT sum(nullif(btrim(freight_value), '')::numeric) FROM raw.order_items)
       OR (SELECT sum(payment_value) FROM core.order_payments) IS DISTINCT FROM
          (SELECT sum(nullif(btrim(payment_value), '')::numeric) FROM raw.order_payments) THEN
        RAISE EXCEPTION 'Money changed between raw and core';
    END IF;
    IF EXISTS (
        (SELECT nullif(btrim(order_status), ''), count(*) FROM raw.orders GROUP BY 1
         EXCEPT SELECT order_status, count(*) FROM core.orders GROUP BY 1)
        UNION ALL
        (SELECT order_status, count(*) FROM core.orders GROUP BY 1
         EXCEPT SELECT nullif(btrim(order_status), ''), count(*) FROM raw.orders GROUP BY 1)
    ) THEN
        RAISE EXCEPTION 'Order status distribution changed';
    END IF;
    IF (SELECT count(*) FROM mart.order_totals) <> (SELECT count(*) FROM core.orders)
       OR (SELECT count(DISTINCT order_id) FROM mart.order_totals) <> (SELECT count(*) FROM core.orders) THEN
        RAISE EXCEPTION 'mart.order_totals lost or multiplied orders';
    END IF;
    IF (SELECT count(*) FROM mart.sales_items) <>
       (SELECT count(*) FROM core.order_items i JOIN core.orders o USING (order_id)
        WHERE o.order_status = 'delivered') THEN
        RAISE EXCEPTION 'mart.sales_items lost or multiplied items';
    END IF;
    IF (SELECT sum(item_amount) FROM mart.sales_items) IS DISTINCT FROM
       (SELECT sum(items_amount) FROM mart.order_totals WHERE order_status = 'delivered') THEN
        RAISE EXCEPTION 'Revenue differs between order and item views';
    END IF;
    IF EXISTS (SELECT 1 FROM mart.order_totals WHERE order_status = 'delivered' AND NOT has_items) THEN
        RAISE EXCEPTION 'Delivered orders without items require review before reports are published';
    END IF;
    RAISE NOTICE 'PASS: source counts, money, statuses, keys and report grain';
END $$;

COMMIT;
