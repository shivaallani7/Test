WITH proc_list AS (
    SELECT column1 AS proc_name FROM VALUES
        ('MY_DB.MY_SCHEMA.MY_PROC_A'),
        ('MY_DB.MY_SCHEMA.MY_PROC_B')
),
direct_calls AS (
    SELECT
        obj.value:"objectName"::STRING AS proc_name_full,
        ah.query_id,
        qh.start_time
    FROM util.it.access_history ah
    JOIN util.it.query_history qh ON ah.query_id = qh.query_id
    , LATERAL FLATTEN(input => ah.direct_objects_accessed) obj
    WHERE obj.value:"objectDomain"::STRING = 'Procedure'
      AND qh.start_time >= DATEADD(month, -3, CURRENT_TIMESTAMP())
),
base_calls AS (
    SELECT
        obj.value:"objectName"::STRING AS proc_name_full,
        ah.query_id,
        qh.start_time
    FROM util.it.access_history ah
    JOIN util.it.query_history qh ON ah.query_id = qh.query_id
    , LATERAL FLATTEN(input => ah.base_objects_accessed) obj
    WHERE obj.value:"objectDomain"::STRING = 'Procedure'
      AND qh.start_time >= DATEADD(month, -3, CURRENT_TIMESTAMP())
),
all_calls AS (
    SELECT DISTINCT proc_name_full, query_id, start_time FROM direct_calls
    UNION
    SELECT DISTINCT proc_name_full, query_id, start_time FROM base_calls
)
SELECT
    tl.proc_name,
    COUNT(ac.query_id)   AS total_access_count,
    MAX(ac.start_time)   AS last_accessed_date
FROM proc_list tl
LEFT JOIN all_calls ac
    ON ac.proc_name_full ILIKE tl.proc_name || '(%'
    OR ac.proc_name_full = tl.proc_name
GROUP BY tl.proc_name
ORDER BY total_access_count DESC;
