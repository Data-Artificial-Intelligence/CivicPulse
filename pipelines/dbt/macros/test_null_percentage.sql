{% test null_percentage_less_than(model, column_name, threshold=0.2) %}
-- Custom test to ensure the percentage of null values in a column does not exceed the threshold
with validation as (
    select
        sum(case when {{ column_name }} is null then 1 else 0 end) * 1.0 / nullif(count(*), 0) as null_ratio
    from {{ model }}
),
validation_errors as (
    select null_ratio
    from validation
    where null_ratio > {{ threshold }}
)
select * from validation_errors
{% endtest %}