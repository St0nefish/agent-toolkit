-- Currently running queries (excludes idle connections)
SELECT
    pid,
    usename,
    state,
    wait_event_type,
    now() - query_start AS duration,
    left(query, 120) AS query
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY query_start
