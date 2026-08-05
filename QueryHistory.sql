WITH table_list AS (
    SELECT column1 AS table_name FROM VALUES
        ('MY_DB.MY_SCHEMA.TABLE_A'),
        ('MY_DB.MY_SCHEMA.TABLE_B')
),
-- reads: SELECTs and any query that referenced the table (incl. via views, procs)
reads AS (
    SELECT
        obj.value:"objectName"::STRING AS table_name,
        qh.query_id,
        qh.query_type,
        qh.start_time,
        ah.root_query_id
    FROM util.it.access_history ah
    JOIN util.it.query_history qh ON ah.query_id = qh.query_id
    , LATERAL FLATTEN(input => ah.base_objects_accessed) obj
    JOIN table_list tl ON obj.value:"objectName"::STRING = tl.table_name
    WHERE qh.start_time >= DATEADD(month, -3, CURRENT_TIMESTAMP())
),
-- writes: INSERT/UPDATE/DELETE/MERGE/COPY/CTAS etc.
writes AS (
    SELECT
        obj.value:"objectName"::STRING AS table_name,
        qh.query_id,
        qh.query_type,
        qh.start_time,
        ah.root_query_id
    FROM util.it.access_history ah
    JOIN util.it.query_history qh ON ah.query_id = qh.query_id
    , LATERAL FLATTEN(input => ah.objects_modified) obj
    JOIN table_list tl ON obj.value:"objectName"::STRING = tl.table_name
    WHERE qh.start_time >= DATEADD(month, -3, CURRENT_TIMESTAMP())
),
combined AS (
    SELECT table_name, query_id, query_type, start_time, root_query_id, 'READ' AS access_type FROM reads
    UNION ALL
    SELECT table_name, query_id, query_type, start_time, root_query_id, 'WRITE' AS access_type FROM writes
),
-- normalize: if the query was run inside a stored procedure, tag it as STORED_PROC_CALL
normalized AS (
    SELECT
        table_name,
        query_id,
        start_time,
        CASE
            WHEN root_query_id IS NOT NULL THEN 'STORED_PROC_CALL'
            ELSE query_type
        END AS op_type
    FROM combined
)
SELECT
    table_name,
    COUNT(*)                                            AS total_access_count,
    MAX(start_time)                                     AS last_accessed_date,
    COUNT_IF(op_type = 'SELECT')                        AS select_count,
    COUNT_IF(op_type = 'INSERT')                         AS insert_count,
    COUNT_IF(op_type = 'UPDATE')                         AS update_count,
    COUNT_IF(op_type = 'DELETE')                         AS delete_count,
    COUNT_IF(op_type = 'MERGE')                          AS merge_count,
    COUNT_IF(op_type = 'COPY')                           AS copy_count,
    COUNT_IF(op_type = 'CREATE_TABLE_AS_SELECT')         AS ctas_count,
    COUNT_IF(op_type = 'STORED_PROC_CALL')               AS stored_proc_call_count,
    -- catch-all for any operation types not explicitly listed above
    COUNT_IF(op_type NOT IN (
        'SELECT','INSERT','UPDATE','DELETE','MERGE','COPY',
        'CREATE_TABLE_AS_SELECT','STORED_PROC_CALL'
    )) AS other_count,
    -- full breakdown as JSON, useful if you want every op_type without missing any
    OBJECT_AGG(op_type, op_count) AS full_operation_breakdown
FROM normalized
JOIN (
    SELECT table_name, op_type, COUNT(*) AS op_count
    FROM normalized
    GROUP BY table_name, op_type
) op_counts
    USING (table_name, op_type)
GROUP BY table_name
ORDER BY total_access_count DESC;
