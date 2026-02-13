-- Connection summary by state and user
SELECT
    usename,
    state,
    count(*) AS count,
    max(now() - query_start) AS max_duration
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY usename, state
ORDER BY count DESC
