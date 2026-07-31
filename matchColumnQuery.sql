WITH ats AS (
    SELECT
        TABLE_NAME AS ats_table_name_orig,
        COLUMN_NAME AS ats_column_name,
        UPPER(TRIM(
            CASE
                WHEN UPPER(TRIM(TABLE_NAME)) LIKE 'AS_REF\_%' ESCAPE '\' 
                    THEN SUBSTR(TABLE_NAME, LEN('AS_REF_') + 1)
                WHEN UPPER(TRIM(TABLE_NAME)) LIKE 'AS\_%' ESCAPE '\' 
                    THEN SUBSTR(TABLE_NAME, LEN('AS_') + 1)
                ELSE TABLE_NAME
            END
        )) AS ats_table_clean,
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
c360_module_map AS (
    SELECT column1 AS table_name, column2 AS module_name
    FROM VALUES
        ('C360_COBRAND_AMEX_SPEND',            'COBRAND'),
        ('C360_COBRAND_CHASE_SPEND',           'COBRAND'),
        ('C360_COBRAND_CARDHOLDER_DETAIL',     'COBRAND'),
        ('C360_COBRAND_CARDHOLDER_FLG_DETAIL', 'COBRAND'),
        ('C360_COBRAND_HUB',                   'COBRAND'),
        ('C360_CUSTOMER_DEMOGRAPHIC_DETAIL',   'PROFILE'),
        ('C360_ACCOUNT_PROFILE',               'PROFILE'),
        ('C360_CONSENT_PROFILE',               'PROFILE'),
        ('C360_ANALYTICAL_CLTV',               'PROFILE'),
        ('C360_EPSILON_TSP',                   'PROFILE'),
        ('C360_PROFILE_HUB',                   'PROFILE'),
        ('C360_TRANS_LOYALTY_BONUS',           'LOYALTY'),
        ('C360_TRANS_LOYALTY_STAY',            'LOYALTY'),
        ('C360_LOYALTY_TRANS_POINT_BAL',       'LOYALTY'),
        ('C360_LOYALTY_PROFILE',               'LOYALTY'),
        ('C360_LOYALTY_HUB',                   'LOYALTY'),
        ('C360_RESERVATION_BRAND_ROOMNIGHTS',  'RESERVATION'),
        ('C360_RESERVATION_HOTEL',             'RESERVATION'),
        ('C360_RESERVATION_EMAIL',             'RESERVATION'),
        ('C360_RESERVATION_BOOKING_CHANNEL',   'RESERVATION'),
        ('C360_RESERVATION_ROOMNIGHTS',        'RESERVATION'),
        ('C360_RESERVATION_HUB',               'RESERVATION'),
        ('C360_RESERVATION_LUXURY_SEGMENT',    'RESERVATION'),
        ('C360_EAT_AROUND_FB',                 'PARTNERSHIPS'),
        ('C360_UBER_PARTNERSHIPS',             'PARTNERSHIPS'),
        ('C360_PARTNERSHIPS_HUB',              'PARTNERSHIPS'),
        ('C360_DIGITAL_INTERACTIONS',          'INTERACTION'),
        ('C360_INTERACTION_MARKETING_EMAIL',   'INTERACTION'),
        ('C360_INTERACTION_HUB',               'INTERACTION'),
        ('C360_ALL_FOLIO_FB_REVENUE',          'FOLIO'),
        ('C360_FOLIO_TRAN_SILK',               'FOLIO'),
        ('C360_TRANSACTION_FOLIO_HUB',         'FOLIO')
    AS t(column1, column2)
),
c360 AS (
    SELECT DISTINCT
        cols.TABLE_NAME AS c360_table_name_orig,
        map.module_name AS c360_module_name,
        cols.COLUMN_NAME AS c360_column_name,
        REPLACE(UPPER(TRIM(cols.TABLE_NAME)), 'C360_', '') AS c360_table_clean,
        UPPER(TRIM(cols.COLUMN_NAME)) AS c360_col_clean
    FROM COMMUNITY.INFORMATION_SCHEMA.COLUMNS cols
    JOIN c360_module_map map
        ON cols.TABLE_NAME = map.table_name
    WHERE cols.TABLE_SCHEMA = 'IDP'
),
ats_combined AS (
    SELECT
        *,
        ats_table_clean || '_' || ats_col_clean AS ats_combined_key
    FROM ats
),
c360_combined AS (
    SELECT
        *,
        c360_table_clean || '_' || c360_col_clean AS c360_combined_key
    FROM c360
),
matched AS (
    SELECT
        a.ats_table_name_orig,
        a.ats_table_clean,
        a.ats_column_name,
        c.c360_module_name,
        c.c360_table_name_orig,
        c.c360_column_name,
        CASE
            WHEN a.ats_combined_key = c.c360_combined_key THEN 'EXACT'
            WHEN CONTAINS(c.c360_combined_key, a.ats_combined_key) THEN 'C360_CONTAINS_ATS'
            WHEN CONTAINS(a.ats_combined_key, c.c360_combined_key) THEN 'ATS_CONTAINS_C360'
            ELSE NULL
        END AS match_type
    FROM ats_combined a
    LEFT JOIN c360_combined c
        ON a.ats_combined_key = c.c360_combined_key
        OR CONTAINS(c.c360_combined_key, a.ats_combined_key)
        OR CONTAINS(a.ats_combined_key, c.c360_combined_key)
),
report_base AS (
    SELECT DISTINCT
        c360_module_name,
        ats_table_name_orig,
        ats_table_clean,
        ats_column_name,
        c360_table_name_orig,
        c360_column_name,
        match_type
    FROM matched
)
SELECT
    COALESCE(c360_module_name, '(NO MODULE - UNMATCHED)') AS module,
    ats_table_name_orig AS ats_table_name_original,
    ats_table_clean AS ats_table_name_cleansed,
    CASE
        WHEN COUNT_IF(match_type IS NOT NULL) > 0 THEN 'MATCHED'
        ELSE 'NOT MATCHED'
    END AS matched_status,
    LISTAGG(
        CASE 
            WHEN match_type IS NOT NULL 
            THEN c360_table_name_orig || '.' || c360_column_name 
        END, 
        '; '
    ) WITHIN GROUP (ORDER BY c360_table_name_orig, c360_column_name) AS matched_c360_table_column_combinations
FROM report_base
GROUP BY module, ats_table_name_orig, ats_table_clean
ORDER BY matched_status DESC, module, ats_table_name_original;
