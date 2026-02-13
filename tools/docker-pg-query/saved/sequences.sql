-- All sequences with current values
SELECT
    schemaname,
    sequencename,
    last_value,
    start_value,
    increment_by,
    max_value
FROM pg_sequences
ORDER BY schemaname, sequencename
