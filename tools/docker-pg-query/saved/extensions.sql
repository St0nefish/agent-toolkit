-- Installed PostgreSQL extensions
SELECT
    extname AS extension,
    extversion AS version,
    n.nspname AS schema
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
ORDER BY extname
