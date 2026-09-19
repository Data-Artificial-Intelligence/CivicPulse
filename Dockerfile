FROM apache/airflow:2.9.0-python3.10

# Switch to root to install system dependencies if needed
USER root

# Install git (required by some dbt/cosmos operations)
RUN apt-get update && apt-get install -y git

# Switch back to airflow user for security
USER airflow

# Copy our requirements file into the container
COPY requirements.txt .

# Install the specific packages we need for this project
# Note: We install Airflow packages here because we removed them from requirements.txt for Windows compatibility
RUN pip install --no-cache-dir \
    "apache-airflow==2.9.0" \
    "astronomer-cosmos==1.4.0" \
    "apache-airflow-providers-amazon==8.29.0" \
    "dbt-core==1.7.13" \
    "dbt-duckdb==1.7.1"