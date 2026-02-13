-- Buffer cache hit ratio (should be > 99% for a healthy database)
SELECT
    sum(heap_blks_read) AS heap_read,
    sum(heap_blks_hit) AS heap_hit,
    CASE WHEN sum(heap_blks_hit) + sum(heap_blks_read) > 0
        THEN round(100.0 * sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)), 2)
        ELSE 0
    END AS hit_ratio_pct
FROM pg_statio_user_tables
