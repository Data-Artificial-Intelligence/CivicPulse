from datetime import datetime, timedelta

from airflow import DAG
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
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="dag_voter_batch_processing",
    start_date=datetime(2026, 9, 1),
    schedule_interval="@daily",
    catchup=False,
    default_args=default_args,
    tags=["civicpulse", "batch", "voter_files"],
) as dag:

    voter_dbt_run = DbtTaskGroup(
        group_id="voter_dbt_transformations",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt"),
        profile_config=profile_config,
        render_config=RenderConfig(select=["stg_voters", "dim_voter"]),
    )

    voter_dbt_test = DbtTaskGroup(
        group_id="voter_data_quality_tests",
        project_config=ProjectConfig(dbt_project_path="/opt/airflow/dbt"),
        profile_config=profile_config,
        render_config=RenderConfig(select=["stg_voters", "dim_voter"]),
    )

    voter_dbt_run >> voter_dbt_test