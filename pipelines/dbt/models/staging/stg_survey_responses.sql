-- Simulates high-velocity microservice survey responses
SELECT 
    'RESP-001' AS response_id,
    'VTR-001' AS voter_id,
    'SRV-001' AS survey_id,
    0.85 AS sentiment_score, -- 0.0 to 1.0
    12.5 AS response_time_seconds,
    '2026-09-15' AS response_date
UNION ALL
SELECT 
    'RESP-002', 'VTR-002', 'SRV-001', 0.45, 8.2, '2026-09-15'