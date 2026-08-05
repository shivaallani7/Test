-- Replace with your list of tables (fully qualified: DB.SCHEMA.TABLE)
SET table_list = ARRAY_CONSTRUCT(
    'MY_DB.MY_SCHEMA.TABLE_A',
    'MY_DB.MY_SCHEMA.TABLE_B'
);

SELECT
    ah.query_id,
    qh.query_text,
    qh.user_name,
    qh.role_name,
    qh.warehouse_name,
    qh.start_time,
    qh.total_elapsed_time / 1000 AS elapsed_sec,
    obj.value:"objectName"::STRING   AS table_name,
    obj.value:"objectDomain"::STRING AS object_type,
    obj.value:"columns" AS columns_accessed
FROM util.it.access_history ah
JOIN util.it.query_history qh
    ON ah.query_id = qh.query_id
, LATERAL FLATTEN(input => ah.base_objects_accessed) obj
WHERE obj.value:"objectName"::STRING IN (SELECT VALUE::STRING FROM TABLE(FLATTEN(INPUT => $table_list)))
  AND qh.start_time >= DATEADD(month, -3, CURRENT_TIMESTAMP())
ORDER BY qh.start_time DESC;
