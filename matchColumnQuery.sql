WITH ats AS (
    SELECT
        TABLE_NAME AS ats_table_name,
        COLUMN_NAME AS ats_column_name,
        DATA_TYPE AS ats_data_type,
        ORDINAL_POSITION AS ats_ordinal_position,
        UPPER(TRIM(COLUMN_NAME)) AS ats_col_clean
    FROM IDP.INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'MAIN'
      AND TABLE_NAME IN (
          SELECT ATTRIBUTE_STORE_NM
          FROM IDP.MAIN.ATTRIBUTE_STORE_MODULES
          WHERE attr_sql_action_freq NOT IN ('RETIRED', 'ONETIME')
      )
      AND UPPER(TRIM(COLUMN_NAME)) NOT IN ('UPDATE_TS', 'CREATE_TS', 'CUST_ALT_ID')
),
c360 AS (
    SELECT DISTINCT
        TABLE_SCHEMA AS c360_table_schema,
        TABLE_NAME AS c360_table_name,
        COLUMN_NAME AS c360_column_name,
        UPPER(TRIM(COLUMN_NAME)) AS c360_col_clean
    FROM COMMUNITY.INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'IDP'
      AND TABLE_NAME IN (
          'C360_RESERVATION_BRAND_ROOMNIGHTS',
          'C360_RESERVATION_HOTEL',
          'C360_RESERVATION_EMAIL',
          'C360_RESERVATION_BOOKING_CHANNEL',
          'C360_RESERVATION_ROOMNIGHTS',
          'C360_RESERVATION_HUB',
          'C360_RESERVATION_LUXURY_SEGMENT'
      )
),
matched AS (
    SELECT
        ats.ats_table_name,
        ats.ats_column_name,
        c360.c360_table_name,
        c360.c360_column_name,
        CASE
            WHEN ats.ats_col_clean = c360.c360_col_clean THEN 'EXACT'
            WHEN CONTAINS(c360.c360_col_clean, ats.ats_col_clean) THEN 'C360_CONTAINS_ATS'
            WHEN CONTAINS(ats.ats_col_clean, c360.c360_col_clean) THEN 'ATS_CONTAINS_C360'
            ELSE NULL
        END AS match_type
    FROM ats
    LEFT JOIN c360
        ON ats.ats_col_clean = c360.c360_col_clean
        OR CONTAINS(c360.c360_col_clean, ats.ats_col_clean)
        OR CONTAINS(ats.ats_col_clean, c360.c360_col_clean)
)
SELECT *
FROM matched
WHERE match_type IS NOT NULL
ORDER BY ats_table_name, ats_column_name;
