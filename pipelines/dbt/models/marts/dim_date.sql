-- Universal date dimension for time-series analysis
-- Note: DuckDB uses standard SQL INTERVAL syntax for date arithmetic
WITH RECURSIVE date_spine AS (
    SELECT CAST('2026-01-01' AS DATE) AS date_day
    UNION ALL
    SELECT date_day + INTERVAL 1 DAY FROM date_spine WHERE date_day < '2026-12-31'
)
SELECT 
    date_day AS date_id,
    EXTRACT(YEAR FROM date_day) AS year,
    EXTRACT(MONTH FROM date_day) AS month,
    EXTRACT(DAY FROM date_day) AS day,
    CASE 
        WHEN EXTRACT(DOW FROM date_day) IN (0, 6) THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type
FROM date_spine