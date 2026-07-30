WITH ats AS (
    SELECT 
        MODULE_NM,
        ATTRIBUTE_STORE_NM,
        UPPER(TRIM(ATTRIBUTE_STORE_NM)) AS attr_nm_clean
    FROM IDP.MAIN.ATTRIBUTE_STORE_MODULES
    WHERE attr_sql_action_freq NOT IN ('RETIRED', 'ONETIME')
),
c360 AS (
    SELECT DISTINCT
        TABLE_SCHEMA,
        TABLE_NAME,
        UPPER(TRIM(TABLE_NAME)) AS table_nm_clean,
        -- strip common prefix to help matching
        REPLACE(UPPER(TRIM(TABLE_NAME)), 'C360_', '') AS table_nm_stripped
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
)
SELECT
    c360.TABLE_SCHEMA,
    c360.TABLE_NAME,
    ats.MODULE_NM,
    ats.ATTRIBUTE_STORE_NM,
    CASE
        WHEN c360.table_nm_clean = ats.attr_nm_clean THEN 'EXACT'
        WHEN c360.table_nm_stripped = ats.attr_nm_clean THEN 'EXACT_AFTER_PREFIX_STRIP'
        WHEN CONTAINS(c360.table_nm_clean, ats.attr_nm_clean)
             OR CONTAINS(ats.attr_nm_clean, c360.table_nm_clean) THEN 'PARTIAL_CONTAINS'
        WHEN CONTAINS(c360.table_nm_stripped, ats.attr_nm_clean)
             OR CONTAINS(ats.attr_nm_clean, c360.table_nm_stripped) THEN 'PARTIAL_CONTAINS_STRIPPED'
        ELSE NULL
    END AS match_type
FROM c360
LEFT JOIN ats
    ON c360.table_nm_clean = ats.attr_nm_clean
    OR c360.table_nm_stripped = ats.attr_nm_clean
    OR CONTAINS(c360.table_nm_clean, ats.attr_nm_clean)
    OR CONTAINS(ats.attr_nm_clean, c360.table_nm_clean)
    OR CONTAINS(c360.table_nm_stripped, ats.attr_nm_clean)
    OR CONTAINS(ats.attr_nm_clean, c360.table_nm_stripped)
QUALIFY match_type IS NOT NULL
ORDER BY c360.TABLE_NAME;
