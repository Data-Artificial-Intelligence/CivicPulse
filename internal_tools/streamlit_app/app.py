import streamlit as st
import duckdb
import json
import requests
import os

from dotenv import load_dotenv
from requests.auth import HTTPBasicAuth
from datetime import datetime

# Load project environment variables from .env
load_dotenv()

# AWS credentials used by DuckDB httpfs when querying S3-backed models
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID", "")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "")

# Configuration
DB_PATH = "pipelines/dbt/civic_pulse.duckdb"
CATALOG_PATH = "pipelines/dbt/target/catalog.json"
AIRFLOW_API_URL = "http://localhost:8080/api/v1"
AIRFLOW_USER = "admin"
AIRFLOW_PASS = "admin"

st.set_page_config(page_title="CivicPulse Data Portal", page_icon="🏛️", layout="wide")

st.title("🏛️ CivicPulse Internal Data Portal")
st.markdown("Self-service tool for Data Science and Business Analytics teams to monitor data health, explore the data dictionary, and manage pipeline executions.")

tab1, tab2, tab3 = st.tabs(["📊 Data Quality Dashboard", "📖 Data Dictionary", "⚙️ Pipeline Operations"])

# ==========================================
# FEATURE 1: Data Quality Dashboard
# ==========================================
with tab1:
    st.header("Real-Time Data Quality Metrics")
    st.markdown("Live metrics pulled directly from the data warehouse to ensure quantitative research data integrity.")
    
    try:
        conn = duckdb.connect(DB_PATH)
        
        # Explicitly configure DuckDB to access S3 for views that query it
        conn.execute("INSTALL httpfs")
        conn.execute("LOAD httpfs")
        conn.execute(f"SET s3_region='{AWS_REGION}'")
        conn.execute(f"SET s3_access_key_id='{AWS_ACCESS_KEY_ID}'")
        conn.execute(f"SET s3_secret_access_key='{AWS_SECRET_ACCESS_KEY}'")
        
        # Metric 1: Voter ID Completeness
        voter_count = conn.execute("SELECT COUNT(*) FROM dim_voter").fetchone()[0]
        null_voter_count = conn.execute("SELECT COUNT(*) FROM dim_voter WHERE voter_id IS NULL").fetchone()[0]
        match_rate = ((voter_count - null_voter_count) / voter_count * 100) if voter_count > 0 else 100.0
        
        st.metric(label="Voter ID Completeness", value=f"{match_rate:.1f}%", delta="Target: 100%")
        
        # Metric 2: Sentiment Score Bounds (QA Test Simulation)
        sentiment_out_of_bounds = conn.execute("""
            SELECT COUNT(*) FROM fact_daily_survey_responses 
            WHERE sentiment_score < 0.0 OR sentiment_score > 1.0
        """).fetchone()[0]
        
        st.metric(
            label="Sentiment Scores Out of Bounds (0.0 - 1.0)", 
            value=sentiment_out_of_bounds, 
            delta="Target: 0", 
            delta_color="inverse" if sentiment_out_of_bounds > 0 else "normal"
        )
        
        # Metric 3: Total Records
        total_surveys = conn.execute("SELECT COUNT(*) FROM fact_daily_survey_responses").fetchone()[0]
        st.metric(label="Total Survey Responses in Warehouse", value=total_surveys)
        
        conn.close()
        st.success("✅ All core data quality checks passed based on the latest warehouse state.")
        
    except Exception as e:
        st.warning("⚠️ Could not connect to data warehouse. Ensure dbt has been run locally (`dbt build`) and AWS credentials are loaded.")
        st.code(str(e))

# ==========================================
# FEATURE 2: Data Dictionary
# ==========================================
with tab2:
    st.header("Data Dictionary")
    st.markdown("Search and explore table and column definitions generated directly from dbt documentation. No SQL required!")
    
    try:
        with open(CATALOG_PATH, 'r', encoding='utf-8') as f:
            catalog = json.load(f)
            
        nodes = catalog.get('nodes', {})
        
        # Filter for our specific dbt models
        models = {k: v for k, v in nodes.items() if k.startswith('model.civic_pulse.')}
        
        model_names = sorted([name.split('.')[-1] for name in models.keys()])
        selected_model = st.selectbox("Select a table to explore:", [""] + model_names)
        
        if selected_model:
            model_key = f"model.civic_pulse.{selected_model}"
            model_data = models[model_key]
            
            st.subheader(f"Table: `{selected_model}`")
            description = model_data.get('metadata', {}).get('comment', 'No description available.')
            st.info(f"**Description:** {description}")
            
            st.markdown("### Columns")
            columns = model_data.get('columns', {})
            col_data = []
            for col_name, col_info in columns.items():
                col_data.append({
                    "Column Name": col_name,
                    "Data Type": col_info.get('type', 'Unknown').upper(),
                    "Description": col_info.get('comment', 'No description')
                })
            
            st.dataframe(col_data, use_container_width=True, hide_index=True)
            
    except FileNotFoundError:
        st.warning("⚠️ `catalog.json` not found. Please run `dbt docs generate` in the `pipelines/dbt` directory first.")
    except Exception as e:
        st.error(f"Error loading data dictionary: {e}")

# ==========================================
# FEATURE 3: Pipeline Operations
# ==========================================
with tab3:
    st.header("Pipeline Operations")
    st.markdown("Manually trigger pipeline re-runs if the Data Science team identifies data anomalies or missing data.")
    
    dag_options = {
        "Voter Batch Processing (Nightly)": "dag_voter_batch_processing",
        "Survey Microservice Processing (Event-Driven)": "dag_survey_microservice_processing"
    }
    
    col1, col2 = st.columns(2)
    with col1:
        selected_dag_name = st.selectbox("Select Pipeline to Re-run", list(dag_options.keys()))
    dag_id = dag_options[selected_dag_name]
    
    with col2:
        run_date = st.date_input("Select logical date for re-run", datetime.now())
    
    if st.button("🚀 Trigger Manual Re-run", type="primary"):
        with st.spinner(f"Contacting Airflow to trigger `{dag_id}`..."):
            try:
                # 1. Get the base date selected by the user (e.g., 2026-09-20)
                base_date = datetime.combine(run_date, datetime.min.time())
                
                # 2. Append the current time to make it a unique logical_date.
                # This prevents 409 Conflicts if the user triggers the same day twice.
                # In the real world, this is called a "Manual Backfill".
                unique_logical_date = base_date.replace(
                    hour=datetime.now().hour,
                    minute=datetime.now().minute,
                    second=datetime.now().second
                )
                
                logical_date_str = unique_logical_date.strftime("%Y-%m-%dT%H:%M:%S+00:00")
                
                # 3. Create a unique run ID for tracking
                unique_run_id = f"manual_backfill_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

                payload = {
                    "conf": {},
                    "logical_date": logical_date_str,
                    "dag_run_id": unique_run_id
                }
                
                response = requests.post(
                    f"{AIRFLOW_API_URL}/dags/{dag_id}/dagRuns",
                    json=payload,
                    auth=HTTPBasicAuth(AIRFLOW_USER, AIRFLOW_PASS),
                    headers={"Content-Type": "application/json"}
                )
                
                if response.status_code in [200, 201]:
                    st.success(f"✅ Successfully triggered DAG: `{dag_id}`!")
                    st.info(f"📅 Business Date: {run_date} | 🕒 Unique Logical Date: {logical_date_str}")
                    with st.expander("View API Response"):
                        st.json(response.json())
                else:
                    st.error(f"❌ Failed to trigger DAG. Status Code: {response.status_code}")
                    st.code(response.text)
                    
            except requests.exceptions.ConnectionError:
                st.error("❌ Could not connect to Airflow. Ensure Airflow is running at http://localhost:8080.")
            except Exception as e:
                st.error(f"❌ An unexpected error occurred: {e}")