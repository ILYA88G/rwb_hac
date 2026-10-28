-- Read-only fingerprints of ALL raw columns, including load metadata.
BEGIN READ ONLY;
SELECT 'customers' AS source_table, count(*) AS rows, md5(coalesce(string_agg(row_hash, '' ORDER BY row_hash), '')) AS content_md5 FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM raw.customers t) hashes
UNION ALL
SELECT 'order_items' AS source_table, count(*) AS rows, md5(coalesce(string_agg(row_hash, '' ORDER BY row_hash), '')) AS content_md5 FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM raw.order_items t) hashes
UNION ALL
SELECT 'order_payments' AS source_table, count(*) AS rows, md5(coalesce(string_agg(row_hash, '' ORDER BY row_hash), '')) AS content_md5 FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM raw.order_payments t) hashes
UNION ALL
SELECT 'order_reviews' AS source_table, count(*) AS rows, md5(coalesce(string_agg(row_hash, '' ORDER BY row_hash), '')) AS content_md5 FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM raw.order_reviews t) hashes
UNION ALL
SELECT 'orders' AS source_table, count(*) AS rows, md5(coalesce(string_agg(row_hash, '' ORDER BY row_hash), '')) AS content_md5 FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM raw.orders t) hashes
UNION ALL
SELECT 'product_category_translation' AS source_table, count(*) AS rows, md5(coalesce(string_agg(row_hash, '' ORDER BY row_hash), '')) AS content_md5 FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM raw.product_category_translation t) hashes
UNION ALL
SELECT 'products' AS source_table, count(*) AS rows, md5(coalesce(string_agg(row_hash, '' ORDER BY row_hash), '')) AS content_md5 FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM raw.products t) hashes
UNION ALL
SELECT 'sellers' AS source_table, count(*) AS rows, md5(coalesce(string_agg(row_hash, '' ORDER BY row_hash), '')) AS content_md5 FROM (SELECT md5(to_jsonb(t)::text) AS row_hash FROM raw.sellers t) hashes
ORDER BY source_table;
COMMIT;
