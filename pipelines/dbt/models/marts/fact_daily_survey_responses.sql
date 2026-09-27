{{ config(materialized='view') }}

-- The central Fact Table connecting survey responses
-- to the available dimensions.
WITH responses AS (
    SELECT * FROM {{ ref('stg_survey_responses') }}
),
voters AS (
    SELECT * FROM {{ ref('dim_voter') }}
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
    CAST(r.response_date AS DATE) AS date_id,
    r.sentiment_score,
    r.response_time_seconds,
    v.county,
    v.year AS voter_year,
    s.pollster_name
FROM responses r
LEFT JOIN voters v 
    ON r.voter_id = v.voter_id
LEFT JOIN surveys s 
    ON r.survey_id = s.survey_id
LEFT JOIN dates d 
    ON CAST(r.response_date AS DATE) = d.date_id
