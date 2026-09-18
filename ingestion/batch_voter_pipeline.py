import pandas as pd
import boto3
import io
from datetime import datetime

# Configuration
S3_BUCKET = "civicpulse-raw-voter-files" # We will create this with Terraform
AWS_REGION = "us-east-1"

def generate_mock_voter_data():
    """Simulates extracting raw voter data from a legacy system or API."""
    data = {
        "voter_id": ["VTR-1001", "VTR-1002", "VTR-1003", "VTR-1004"],
        "first_name": ["John", "Jane", "Robert", "Alice"],
        "last_name": ["Doe", "Smith", "Johnson", "Williams"],
        "county": ["Fairfax", "Fairfax", "Arlington", "Arlington"],
        "registration_status": ["Active", "Active", "Inactive", "Active"],
        "party_affiliation": ["Democrat", "Independent", "Republican", "Democrat"],
        "last_updated": ["2026-09-15", "2026-09-16", "2026-09-15", "2026-09-17"]
    }
    return pd.DataFrame(data)

def clean_and_partition_data(df: pd.DataFrame):
    """Cleans data and prepares it for partitioned Parquet storage."""
    # 1. Data Quality: Drop rows with missing critical fields
    df = df.dropna(subset=["voter_id", "county"])
    
    # 2. Data Transformation: Standardize text
    df["party_affiliation"] = df["party_affiliation"].str.title()
    df["last_updated"] = pd.to_datetime(df["last_updated"])
    df["year"] = df["last_updated"].dt.year
    
    return df

def upload_to_s3_partitioned(df: pd.DataFrame):
    """Uploads DataFrame to S3 partitioned by year and county."""
    s3 = boto3.client("s3", region_name=AWS_REGION)
    
    # Group by partition keys
    for (year, county), group in df.groupby(["year", "county"]):
        # Drop partition columns from the actual data payload (best practice)
        data_to_write = group.drop(columns=["year", "county"])
        
        # Convert to Parquet in memory
        parquet_buffer = io.BytesIO()
        data_to_write.to_parquet(parquet_buffer, index=False, engine="pyarrow")
        
        # Define S3 partitioned path: s3://bucket/year=2026/county=Fairfax/data.parquet
        s3_key = f"year={year}/county={county}/data.parquet"
        
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=s3_key,
            Body=parquet_buffer.getvalue(),
            ContentType="application/octet-stream"
        )
        print(f"✅ Successfully uploaded partition: {s3_key}")

if __name__ == "__main__":
    print("🚀 Starting Batch Voter Pipeline...")
    raw_df = generate_mock_voter_data()
    clean_df = clean_and_partition_data(raw_df)
    upload_to_s3_partitioned(clean_df)
    print("🎉 Batch Pipeline Completed Successfully!")