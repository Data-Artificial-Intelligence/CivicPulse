{{ config(materialized='view') }}

-- Read partitioned Parquet files directly from S3 using DuckDB's httpfs extension
-- Note: year and county are partition columns, automatically available in the query
SELECT 
    voter_id,
    registration_status,
    party_affiliation,
    year,
    county
FROM read_parquet('s3://civicpulse-raw-voter-files/year=*/county=*/data.parquet')
