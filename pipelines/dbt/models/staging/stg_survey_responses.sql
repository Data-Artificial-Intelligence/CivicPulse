{{ config(materialized='view') }}

-- Read partitioned JSON files directly from S3 using DuckDB's httpfs extension
SELECT 
    message_id AS response_id,
    voter_id,
    survey_id,
    CAST(sentiment_score AS FLOAT) AS sentiment_score,
    CAST(response_time_seconds AS FLOAT) AS response_time_seconds,
    CAST(ingestion_timestamp AS TIMESTAMP) AS response_date
FROM read_json_auto('s3://civicpulse-raw-surveys/raw_surveys/date=*/survey_*.json')