WITH staged AS (
    SELECT * FROM {{ ref('stg_voters') }}
)
SELECT 
    voter_id,
    first_name,
    last_name,
    registration_status,
    party_affiliation,
    geography_id
FROM staged