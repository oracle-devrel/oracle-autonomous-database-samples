-- PostgreSQL view creation script.
-- Execute with: psql -f views.sql

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

CREATE OR REPLACE VIEW "ALL_PART_TABLES" AS
WITH "PARTITION_DETAILS" AS (
    SELECT
        parent_ns.nspname AS "OWNER",
        parent.relname AS "TABLE_NAME",
        parent.oid AS "PARENT_OID",
        count(child.oid) AS "PARTITION_COUNT",
        pg_partitioned_table.partstrat AS "PARTSTRAT",
        pg_partitioned_table.partattrs AS "PARTITION_COLUMNS"
    FROM pg_inherits i
    JOIN pg_class child
         ON child.oid = i.inhrelid
    JOIN pg_class parent
         ON parent.oid = i.inhparent
    JOIN pg_namespace parent_ns
         ON parent.relnamespace = parent_ns.oid
    JOIN pg_partitioned_table
         ON parent.oid = pg_partitioned_table.partrelid
    WHERE parent.relkind = 'p'
    GROUP BY
        parent_ns.nspname,
        parent.relname,
        parent.oid,
        pg_partitioned_table.partstrat,
        pg_partitioned_table.partattrs
),
"PARTITIONING_KEYS" AS (
    SELECT
        ppt.partrelid AS "PARENT_OID",
        array_length(ppt.partattrs, 1) AS "PARTITIONING_KEY_COUNT"
    FROM pg_partitioned_table ppt
    WHERE ppt.partattrs IS NOT NULL
)
SELECT
    pd."OWNER",
    pd."TABLE_NAME",
    pd."PARTITION_COUNT",
    pk."PARTITIONING_KEY_COUNT",
    CASE
        WHEN pd."PARTSTRAT" = 'r' THEN 'RANGE'
        WHEN pd."PARTSTRAT" = 'l' THEN 'LIST'
        WHEN pd."PARTSTRAT" = 'h' THEN 'HASH'
        ELSE 'UNKNOWN'
    END AS "PARTITIONING_TYPE"
FROM "PARTITION_DETAILS" pd
JOIN "PARTITIONING_KEYS" pk
  ON pd."PARENT_OID" = pk."PARENT_OID"
ORDER BY
    pd."OWNER",
    pd."TABLE_NAME";

CREATE OR REPLACE VIEW "ALL_TAB_PARTITIONS" AS
SELECT
    ns.nspname     AS "TABLE_OWNER",
    parent.relname AS "TABLE_NAME",
    child.relname  AS "PARTITION_NAME",
    ROW_NUMBER() OVER (
        PARTITION BY parent.oid
        ORDER BY child.oid
    ) AS "PARTITION_POSITION",
    CASE
      WHEN pg_get_expr(child.relpartbound, child.oid) ~ 'TO \(MAXVALUE\)'
      THEN 'MAXVALUE'
      ELSE trim(
             BOTH ''''
             FROM regexp_replace(
                    pg_get_expr(child.relpartbound, child.oid),
                    '.*TO \((.*)\)$',
                    '\1'
                  )
           )
    END AS "HIGH_VALUE",
    LENGTH(
      CASE
        WHEN pg_get_expr(child.relpartbound, child.oid) ~ 'TO \(MAXVALUE\)'
        THEN 'MAXVALUE'
        ELSE trim(
               BOTH ''''
               FROM regexp_replace(
                      pg_get_expr(child.relpartbound, child.oid),
                      '.*TO \((.*)\)$',
                      '\1'
                    )
             )
      END
    ) AS "HIGH_VALUE_LENGTH",
    CASE pt.partstrat
      WHEN 'r' THEN 'RANGE'
      WHEN 'l' THEN 'LIST'
      WHEN 'h' THEN 'HASH'
    END AS "PARTITIONING_TYPE",
    pt.partnatts AS "PARTITION_KEY_COUNT"
FROM pg_inherits i
JOIN pg_class parent
     ON parent.oid = i.inhparent
JOIN pg_class child
     ON child.oid = i.inhrelid
JOIN pg_namespace ns
     ON ns.oid = parent.relnamespace
JOIN pg_partitioned_table pt
     ON pt.partrelid = parent.oid
WHERE parent.relkind = 'p';
