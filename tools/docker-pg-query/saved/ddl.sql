-- Reconstruct CREATE TABLE DDL for a table (columns, types, constraints)
-- @param 1 Table name (e.g. users or public.users)
WITH parts AS (
    SELECT 0 AS sort_key, 0 AS sub_key,
        'CREATE TABLE ' || c.relnamespace::regnamespace || '.' || c.relname || ' (' AS line
    FROM pg_class c
    WHERE c.oid = '{{1}}'::regclass
    UNION ALL
    SELECT 1, a.attnum,
        '  ' || a.attname || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod)
        || CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END
        || CASE WHEN d.adbin IS NOT NULL THEN ' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid) ELSE '' END
    FROM pg_attribute a
    LEFT JOIN pg_attrdef d ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE a.attrelid = '{{1}}'::regclass
      AND a.attnum > 0
      AND NOT a.attisdropped
    UNION ALL
    SELECT 2, 0,
        '  CONSTRAINT ' || conname || ' ' || pg_get_constraintdef(oid)
    FROM pg_constraint
    WHERE conrelid = '{{1}}'::regclass
    UNION ALL
    SELECT 3, 0, ');'
),
ordered AS (
    SELECT line, sort_key, sub_key,
        lead(sort_key) OVER (ORDER BY sort_key, sub_key) AS next_sort
    FROM parts
)
SELECT CASE
    WHEN sort_key > 0 AND sort_key < 3 AND next_sort IS NOT NULL AND next_sort < 3
        THEN line || ','
    ELSE line
END AS ddl
FROM ordered
ORDER BY sort_key, sub_key
