from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, RenderConfig

from utils import alert_on_failure

profile_config = ProfileConfig(
    profile_name="civic_pulse",
    target_name="dev",
    profiles_yml_filepath="/opt/airflow/dbt/profiles.yml",
)

default_args = {
    "owner": "data_engineering",
    "depends_on_past": False,
    "on_failure_callback": alert_on_failure,
    "retries": 2,
    "retry_delay": timedelta(minutes=3),
}

with DAG(
    dag_id="dag_survey_microservice_processing",
    start_date=datetime(2026, 9, 1),
    schedule_interval="@daily",
    catchup=False,
    default_args=default_args,
    tags=["civicpulse", "microservice", "survey_data"],
) as dag:

    wait_for_s3_survey_data = S3KeySensor(
        task_id="wait_for_s3_survey_data",
        bucket_name="civicpulse-raw-surveys",
        bucket_key="raw_surveys/date=*/survey_*.json",
        wildcard_match=True,
        aws_conn_id="aws_default",
        timeout=24*60 * 60,
        poke_interval=300,
    )

    survey_dbt_run = DbtTaskGroup(
        group_id="survey_dbt_transformations",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt"),
        profile_config=profile_config,
        render_config=RenderConfig(
            select=["stg_survey_responses", "dim_survey_metadata", "fact_daily_survey_responses"]
        ),
    )

    survey_dbt_test = DbtTaskGroup(
        group_id="survey_data_quality_tests",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt"),
        profile_config=profile_config,
        render_config=RenderConfig(select=["fact_daily_survey_responses"]),
    )

    wait_for_s3_survey_data >> survey_dbt_run >> survey_dbt_test