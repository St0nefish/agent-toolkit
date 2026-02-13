-- Top tables by row count and disk usage
SELECT
    schemaname,
    relname AS table_name,
    n_live_tup AS row_count,
    pg_size_pretty(pg_total_relation_size(schemaname || '.' || relname)) AS total_size
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC
LIMIT 20
