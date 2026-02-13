-- Tables using TOAST storage (large-object overflow)
SELECT
    c.relnamespace::regnamespace AS schema_name,
    c.relname AS table_name,
    t.relname AS toast_table,
    pg_size_pretty(pg_relation_size(t.oid)) AS toast_size,
    pg_size_pretty(pg_relation_size(c.oid)) AS table_size,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_class t ON c.reltoastrelid = t.oid
WHERE pg_relation_size(t.oid) > 0
ORDER BY pg_relation_size(t.oid) DESC
LIMIT 20
