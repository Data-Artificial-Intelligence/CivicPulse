-- The central Fact Table connecting all dimensions
WITH responses AS (
    SELECT * FROM {{ ref('stg_survey_responses') }}
),
voters AS (
    SELECT * FROM {{ ref('dim_voter') }}
),
geography AS (
    SELECT * FROM {{ ref('dim_geography') }}
),
surveys AS (
    SELECT * FROM {{ ref('dim_survey_metadata') }}
),
dates AS (
    SELECT * FROM {{ ref('dim_date') }}
)

SELECT 
    r.response_id,
    r.voter_id,
    r.survey_id,
    v.geography_id,
    CAST(r.response_date AS DATE) AS date_id,
    r.sentiment_score,
    r.response_time_seconds,
    g.district_name,
    s.pollster_name
FROM responses r
LEFT JOIN voters v ON r.voter_id = v.voter_id
LEFT JOIN geography g ON v.geography_id = g.geography_id
LEFT JOIN surveys s ON r.survey_id = s.survey_id
LEFT JOIN dates d ON CAST(r.response_date AS DATE) = d.date_id