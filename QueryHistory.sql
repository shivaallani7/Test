WITH table_list AS (
    SELECT column1 AS table_name FROM VALUES
        ('MY_DB.MY_SCHEMA.TABLE_A'),
        ('MY_DB.MY_SCHEMA.TABLE_B')
),
reads AS (
    SELECT
        obj.value:"objectName"::STRING AS table_name,
        qh.query_id,
        qh.query_type,
        qh.user_name,
        qh.start_time,
        ah.root_query_id
    FROM util.it.access_history ah
    JOIN util.it.query_history qh ON ah.query_id = qh.query_id
    , LATERAL FLATTEN(input => ah.base_objects_accessed) obj
    JOIN table_list tl ON obj.value:"objectName"::STRING = tl.table_name
    WHERE qh.start_time >= DATEADD(month, -3, CURRENT_TIMESTAMP())
),
writes AS (
    SELECT
        obj.value:"objectName"::STRING AS table_name,
        qh.query_id,
        qh.query_type,
        qh.user_name,
        qh.start_time,
        ah.root_query_id
    FROM util.it.access_history ah
    JOIN util.it.query_history qh ON ah.query_id = qh.query_id
    , LATERAL FLATTEN(input => ah.objects_modified) obj
    JOIN table_list tl ON obj.value:"objectName"::STRING = tl.table_name
    WHERE qh.start_time >= DATEADD(month, -3, CURRENT_TIMESTAMP())
),
combined AS (
    SELECT table_name, query_id, query_type, user_name, start_time, root_query_id, 'READ' AS access_type FROM reads
    UNION ALL
    SELECT table_name, query_id, query_type, user_name, start_time, root_query_id, 'WRITE' AS access_type FROM writes
),
normalized AS (
    SELECT
        table_name,
        query_id,
        user_name,
        start_time,
        CASE
            WHEN root_query_id IS NOT NULL THEN 'STORED_PROC_CALL'
            ELSE query_type
        END AS op_type
    FROM combined
),
-- overall summary stats per table
summary AS (
    SELECT
        table_name,
        COUNT(*)                                     AS total_access_count,
        MAX(start_time)                               AS last_accessed_date,
        COUNT_IF(op_type = 'SELECT')                  AS select_count,
        COUNT_IF(op_type = 'INSERT')                  AS insert_count,
        COUNT_IF(op_type = 'UPDATE')                  AS update_count,
        COUNT_IF(op_type = 'DELETE')                  AS delete_count,
        COUNT_IF(op_type = 'MERGE')                   AS merge_count,
        COUNT_IF(op_type = 'COPY')                    AS copy_count,
        COUNT_IF(op_type = 'CREATE_TABLE_AS_SELECT')  AS ctas_count,
        COUNT_IF(op_type = 'STORED_PROC_CALL')        AS stored_proc_call_count,
        COUNT_IF(op_type NOT IN (
            'SELECT','INSERT','UPDATE','DELETE','MERGE','COPY',
            'CREATE_TABLE_AS_SELECT','STORED_PROC_CALL'
        )) AS other_count
    FROM normalized
    GROUP BY table_name
),
-- operation type breakdown per table
op_counts AS (
    SELECT table_name, op_type, COUNT(*) AS op_count
    FROM normalized
    GROUP BY table_name, op_type
),
op_breakdown AS (
    SELECT
        table_name,
        OBJECT_AGG(op_type, op_count) AS full_operation_breakdown
    FROM op_counts
    GROUP BY table_name
),
-- user breakdown per table: total accesses by each user
user_counts AS (
    SELECT table_name, user_name, COUNT(*) AS user_access_count
    FROM normalized
    GROUP BY table_name, user_name
),
user_breakdown AS (
    SELECT
        table_name,
        OBJECT_AGG(user_name, user_access_count) AS access_count_by_user
    FROM user_counts
    GROUP BY table_name
)
SELECT
    s.table_name,
    s.total_access_count,
    s.last_accessed_date,
    s.select_count,
    s.insert_count,
    s.update_count,
    s.delete_count,
    s.merge_count,
    s.copy_count,
    s.ctas_count,
    s.stored_proc_call_count,
    s.other_count,
    ob.full_operation_breakdown,
    ub.access_count_by_user
FROM summary s
JOIN op_breakdown ob USING (table_name)
JOIN user_breakdown ub USING (table_name)
ORDER BY s.total_access_count DESC;
