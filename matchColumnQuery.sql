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
c360_module_map AS (
    SELECT column1 AS table_name, column2 AS module_name
    FROM VALUES
        -- COBRAND
        ('C360_COBRAND_AMEX_SPEND',            'COBRAND'),
        ('C360_COBRAND_CHASE_SPEND',           'COBRAND'),
        ('C360_COBRAND_CARDHOLDER_DETAIL',     'COBRAND'),
        ('C360_COBRAND_CARDHOLDER_FLG_DETAIL', 'COBRAND'),
        ('C360_COBRAND_HUB',                   'COBRAND'),

        -- PROFILE
        ('C360_CUSTOMER_DEMOGRAPHIC_DETAIL',   'PROFILE'),
        ('C360_ACCOUNT_PROFILE',               'PROFILE'),
        ('C360_CONSENT_PROFILE',               'PROFILE'),
        ('C360_ANALYTICAL_CLTV',               'PROFILE'),
        ('C360_EPSILON_TSP',                   'PROFILE'),
        ('C360_PROFILE_HUB',                   'PROFILE'),

        -- LOYALTY
        ('C360_TRANS_LOYALTY_BONUS',           'LOYALTY'),
        ('C360_TRANS_LOYALTY_STAY',            'LOYALTY'),
        ('C360_LOYALTY_TRANS_POINT_BAL',       'LOYALTY'),
        ('C360_LOYALTY_PROFILE',               'LOYALTY'),
        ('C360_LOYALTY_HUB',                   'LOYALTY'),

        -- RESERVATION
        ('C360_RESERVATION_BRAND_ROOMNIGHTS',  'RESERVATION'),
        ('C360_RESERVATION_HOTEL',             'RESERVATION'),
        ('C360_RESERVATION_EMAIL',             'RESERVATION'),
        ('C360_RESERVATION_BOOKING_CHANNEL',   'RESERVATION'),
        ('C360_RESERVATION_ROOMNIGHTS',        'RESERVATION'),
        ('C360_RESERVATION_HUB',               'RESERVATION'),
        ('C360_RESERVATION_LUXURY_SEGMENT',    'RESERVATION'),

        -- PARTNERSHIPS
        ('C360_EAT_AROUND_FB',                 'PARTNERSHIPS'),
        ('C360_UBER_PARTNERSHIPS',             'PARTNERSHIPS'),
        ('C360_PARTNERSHIPS_HUB',              'PARTNERSHIPS'),

        -- INTERACTION
        ('C360_DIGITAL_INTERACTIONS',          'INTERACTION'),
        ('C360_INTERACTION_MARKETING_EMAIL',   'INTERACTION'),
        ('C360_INTERACTION_HUB',               'INTERACTION'),

        -- FOLIO
        ('C360_ALL_FOLIO_FB_REVENUE',          'FOLIO'),
        ('C360_FOLIO_TRAN_SILK',               'FOLIO'),
        ('C360_TRANSACTION_FOLIO_HUB',         'FOLIO')
    AS t(column1, column2)
),
c360 AS (
    SELECT DISTINCT
        cols.TABLE_SCHEMA AS c360_table_schema,
        cols.TABLE_NAME AS c360_table_name,
        map.module_name AS c360_module_name,
        cols.COLUMN_NAME AS c360_column_name,
        UPPER(TRIM(cols.COLUMN_NAME)) AS c360_col_clean
    FROM COMMUNITY.INFORMATION_SCHEMA.COLUMNS cols
    JOIN c360_module_map map
        ON cols.TABLE_NAME = map.table_name
    WHERE cols.TABLE_SCHEMA = 'IDP'
),
matched AS (
    SELECT
        ats.ats_table_name,
        ats.ats_column_name,
        c360.c360_module_name,
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
SELECT
    c360_module_name AS module_name,
    ats_table_name,
    ats_column_name,
    c360_table_name,
    c360_column_name,
    match_type
FROM matched
WHERE match_type IS NOT NULL
ORDER BY module_name, ats_table_name, ats_column_name;
