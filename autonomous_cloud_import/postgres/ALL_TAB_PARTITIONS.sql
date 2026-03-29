CREATE OR REPLACE VIEW "ALL_TAB_PARTITIONS" AS
SELECT
    ns.nspname     AS "TABLE_OWNER",
    parent.relname AS "TABLE_NAME",
    child.relname  AS "PARTITION_NAME",

    -- Oracle-style partition position
    ROW_NUMBER() OVER (
        PARTITION BY parent.oid
        ORDER BY child.oid
    ) AS "PARTITION_POSITION",

    -- Oracle-style HIGH_VALUE (upper bound only, no quotes)
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

    -- Length of HIGH_VALUE (Oracle compatibility)
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

    -- Partitioning type (Oracle naming)
    CASE pt.partstrat
      WHEN 'r' THEN 'RANGE'
      WHEN 'l' THEN 'LIST'
      WHEN 'h' THEN 'HASH'
    END AS "PARTITIONING_TYPE",

    -- Number of partition key columns
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