CREATE OR REPLACE VIEW "ALL_PART_KEY_COLUMNS" AS
SELECT
    ns.nspname                     AS "OWNER",
    c.relname                      AS "NAME",
    'TABLE'                        AS "OBJECT_TYPE",
    a.attname                      AS "COLUMN_NAME",
    ord.ordinality                 AS "COLUMN_POSITION"

FROM pg_partitioned_table pt
JOIN pg_class c
     ON c.oid = pt.partrelid
JOIN pg_namespace ns
     ON ns.oid = c.relnamespace

-- explode partition key column numbers
JOIN LATERAL unnest(pt.partattrs)
     WITH ORDINALITY AS ord(attnum, ordinality)
     ON true

JOIN pg_attribute a
     ON a.attrelid = c.oid
    AND a.attnum   = ord.attnum

ORDER BY
    "OWNER",
    "NAME",
    "COLUMN_POSITION";