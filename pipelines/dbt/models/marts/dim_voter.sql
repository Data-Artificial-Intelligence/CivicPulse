{{ config(materialized='table') }}

-- Dimension table for voters
-- Built from staged voter data from S3
SELECT 
    voter_id,
    registration_status,
    party_affiliation,
    year,
    county,
    -- Create a composite key for the dimension
    {{ dbt_utils.generate_surrogate_key(['voter_id', 'year']) }} AS voter_dim_id,
    CURRENT_TIMESTAMP AS created_at
FROM {{ ref('stg_voters') }}