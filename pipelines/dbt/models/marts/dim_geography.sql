WITH staged AS (
    SELECT * FROM {{ ref('stg_geography') }}
)
SELECT 
    geography_id,
    district_name,
    precinct_name,
    demographic_type
FROM staged