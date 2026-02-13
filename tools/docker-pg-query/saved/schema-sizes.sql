-- Disk usage per schema
SELECT
    schemaname,
    count(*) AS table_count,
    pg_size_pretty(sum(pg_total_relation_size(schemaname || '.' || tablename))) AS total_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
GROUP BY schemaname
ORDER BY sum(pg_total_relation_size(schemaname || '.' || tablename)) DESC
