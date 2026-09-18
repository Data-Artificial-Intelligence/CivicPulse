from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import boto3
import json
import os
import uuid

app = FastAPI(title="CivicPulse Survey Ingestion API")

# Pydantic model for data validation at the API gateway layer
class SurveyResponse(BaseModel):
    voter_id: str = Field(..., description="Unique voter identifier")
    survey_id: str = Field(..., description="Unique survey identifier")
    sentiment_score: float = Field(..., ge=0.0, le=1.0, description="Sentiment between 0.0 and 1.0")
    response_time_seconds: float = Field(..., gt=0.0)

# AWS Configuration
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "https://sqs.us-east-1.amazonaws.com/123456789012/civicpulse-survey-queue")

sqs_client = boto3.client("sqs", region_name=AWS_REGION)

@app.post("/survey", status_code=202)
async def ingest_survey_response(response: SurveyResponse):
    """
    Receives a survey response and pushes it to an SQS queue for asynchronous processing.
    This ensures high availability and decouples ingestion from transformation.
    """
    try:
        # Add metadata for tracing
        payload = response.dict()
        payload["ingestion_timestamp"] = "2026-09-19T12:00:00Z" # Simulated current time
        payload["message_id"] = str(uuid.uuid4())

        # Send to SQS
        sqs_response = sqs_client.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps(payload),
            MessageAttributes={
                "DataType": {"StringValue": "String", "DataType": "String"},
                "VoterId": {"StringValue": response.voter_id, "DataType": "String"}
            }
        )
        
        return {
            "status": "accepted",
            "message": "Survey response queued successfully",
            "sqs_message_id": sqs_response["MessageId"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to queue message: {str(e)}")

# To run locally: uvicorn ingestion.survey_api.app.main:app --reload