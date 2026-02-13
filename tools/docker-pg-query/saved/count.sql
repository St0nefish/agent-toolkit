-- Count rows in a table (schema-qualified name accepted)
-- @param 1 Table name (e.g. public.users or just users)
SELECT COUNT(*) AS row_count FROM {{1}}
