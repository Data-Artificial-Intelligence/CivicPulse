WITH staged AS (
    SELECT * FROM {{ ref('stg_survey_metadata') }}
)
SELECT 
    survey_id,
    question_text,
    pollster_name,
    CAST(survey_date AS DATE) AS survey_date
FROM staged