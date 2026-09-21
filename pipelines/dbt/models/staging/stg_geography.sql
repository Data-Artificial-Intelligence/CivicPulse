-- Simulates raw geography/precinct data
SELECT 
    'GEO-101' AS geography_id,
    'District 5' AS district_name,
    'Precinct A' AS precinct_name,
    'Urban' AS demographic_type
UNION ALL
SELECT 
    'GEO-102', 'District 8', 'Precinct B', 'Suburban'