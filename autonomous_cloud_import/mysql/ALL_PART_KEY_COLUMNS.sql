CREATE OR REPLACE VIEW ALL_PART_KEY_COLUMNS AS
WITH part_tables AS (
    -- one row per partitioned table
    SELECT DISTINCT
        TABLE_SCHEMA,
        TABLE_NAME,
        PARTITION_EXPRESSION
    FROM information_schema.PARTITIONS
    WHERE PARTITION_NAME IS NOT NULL
      AND PARTITION_EXPRESSION IS NOT NULL
),
key_list AS (
    SELECT
        TABLE_SCHEMA AS OWNER,
        TABLE_NAME   AS NAME,

        -- extract text inside parentheses
        TRIM(
          BOTH ')'
          FROM TRIM(
            BOTH '('
            FROM SUBSTRING_INDEX(PARTITION_EXPRESSION, '(', -1)
          )
        ) AS key_list
    FROM part_tables
)
SELECT
    k.OWNER,
    k.NAME,
    'TABLE' AS OBJECT_TYPE,
    TRIM(BOTH '`' FROM
         SUBSTRING_INDEX(
           SUBSTRING_INDEX(k.key_list, ',', n.n),
           ',', -1
         )
    ) AS COLUMN_NAME,
    n.n AS COLUMN_POSITION
FROM key_list k
JOIN (
    SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL
    SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL
    SELECT 7 UNION ALL SELECT 8
) n
  ON n.n <= 1 + LENGTH(k.key_list) - LENGTH(REPLACE(k.key_list, ',', ''))
-- exclude expression-based partitions
WHERE k.key_list NOT REGEXP '[()]'
ORDER BY
    k.OWNER,
    k.NAME,
    COLUMN_POSITION;