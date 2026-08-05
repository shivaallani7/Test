WITH proc_list AS (
    SELECT column1 AS proc_name FROM VALUES
        ('MY_DB.MY_SCHEMA.MY_PROC_A'),
        ('MY_DB.MY_SCHEMA.MY_PROC_B')
),
direct_calls AS (
    SELECT
        obj.value:"objectName"::STRING AS proc_name_full,
        ah.query_id,
        qh.user_name,
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
        qh.user_name,
        qh.start_time
    FROM util.it.access_history ah
    JOIN util.it.query_history qh ON ah.query_id = qh.query_id
    , LATERAL FLATTEN(input => ah.base_objects_accessed) obj
    WHERE obj.value:"objectDomain"::STRING = 'Procedure'
      AND qh.start_time >= DATEADD(month, -3, CURRENT_TIMESTAMP())
),
all_calls AS (
    SELECT DISTINCT proc_name_full, query_id, user_name, start_time FROM direct_calls
    UNION
    SELECT DISTINCT proc_name_full, query_id, user_name, start_time FROM base_calls
),
-- resolve each call to its canonical proc_name from proc_list (handles signature suffixes)
matched_calls AS (
    SELECT
        tl.proc_name,
        ac.query_id,
        ac.user_name,
        ac.start_time
    FROM all_calls ac
    JOIN proc_list tl
        ON ac.proc_name_full ILIKE tl.proc_name || '(%'
        OR ac.proc_name_full = tl.proc_name
),
-- overall summary per proc
summary AS (
    SELECT
        proc_name,
        COUNT(*)         AS total_access_count,
        MAX(start_time)  AS last_accessed_date
    FROM matched_calls
    GROUP BY proc_name
),
-- per-user counts per proc
user_counts AS (
    SELECT proc_name, user_name, COUNT(*) AS user_access_count
    FROM matched_calls
    GROUP BY proc_name, user_name
),
user_breakdown AS (
    SELECT
        proc_name,
        OBJECT_AGG(user_name, user_access_count) AS access_count_by_user
    FROM user_counts
    GROUP BY proc_name
)
SELECT
    tl.proc_name,
    COALESCE(s.total_access_count, 0)     AS total_access_count,
    s.last_accessed_date,
    ub.access_count_by_user
FROM proc_list tl
LEFT JOIN summary s        ON tl.proc_name = s.proc_name
LEFT JOIN user_breakdown ub ON tl.proc_name = ub.proc_name
ORDER BY total_access_count DESC;
