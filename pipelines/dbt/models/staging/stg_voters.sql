-- Simulates raw voter file data from S3
SELECT 
    'VTR-001' AS voter_id,
    'John' AS first_name,
    'Doe' AS last_name,
    'Active' AS registration_status,
    'Democrat' AS party_affiliation,
    'GEO-101' AS geography_id
UNION ALL
SELECT 
    'VTR-002', 'Jane', 'Smith', 'Active', 'Independent', 'GEO-102'