CREATE OR REPLACE VIEW "ALL_PART_TABLES" AS
WITH "PARTITION_DETAILS" AS (
    SELECT
        parent_ns.nspname AS "OWNER",
        parent.relname AS "TABLE_NAME",
        parent.oid AS "PARENT_OID",
        count(child.oid) AS "PARTITION_COUNT",  -- Count partitions
        pg_partitioned_table.partstrat AS "PARTSTRAT", -- Partition strategy (RANGE, LIST, HASH)
        pg_partitioned_table.partattrs AS "PARTITION_COLUMNS" -- Column numbers involved in partitioning
    FROM
        pg_inherits i
        JOIN pg_class child ON child.oid = i.inhrelid
        JOIN pg_class parent ON parent.oid = i.inhparent
        JOIN pg_namespace parent_ns ON parent.relnamespace = parent_ns.oid
        JOIN pg_partitioned_table ON parent.oid = pg_partitioned_table.partrelid
    WHERE
        parent.relkind = 'p'  -- Only partitioned tables
    GROUP BY
        parent_ns.nspname, parent.relname, parent.oid, pg_partitioned_table.partstrat, pg_partitioned_table.partattrs
),
"PARTITIONING_KEYS" AS (
    SELECT
        ppt.partrelid AS "PARENT_OID",
        -- Count the number of partitioning columns by counting entries in partattrs
        array_length(ppt.partattrs, 1) AS "PARTITIONING_KEY_COUNT"  
    FROM
        pg_partitioned_table ppt
    WHERE
        ppt.partattrs IS NOT NULL -- Only count if there are partition columns
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
FROM
    "PARTITION_DETAILS" pd
JOIN
    "PARTITIONING_KEYS" pk ON pd."PARENT_OID" = pk."PARENT_OID"
ORDER BY
    pd."OWNER", pd."TABLE_NAME";