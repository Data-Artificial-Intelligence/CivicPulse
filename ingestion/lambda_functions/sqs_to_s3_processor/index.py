import json
import boto3
import os
from datetime import datetime

s3_client = boto3.client('s3')

# Configuration (Injected by Terraform)
TARGET_BUCKET = os.environ.get('TARGET_BUCKET', 'civicpulse-raw-surveys')

def lambda_handler(event, context):
    """
    Triggered by SQS. Processes batched messages and writes them to S3.
    """
    print(f"Received event: {json.dumps(event)}")
    
    for record in event['Records']:
        try:
            # 1. Parse the SQS message body
            body = json.loads(record['body'])
            
            # 2. Basic Data Quality Validation
            required_fields = ['voter_id', 'survey_id', 'sentiment_score']
            if not all(field in body for field in required_fields):
                print(f"❌ Validation failed: Missing required fields in {body}")
                continue # In production, send to a Dead Letter Queue (DLQ)
            
            if not (0.0 <= body['sentiment_score'] <= 1.0):
                print(f"❌ Validation failed: sentiment_score out of bounds in {body}")
                continue

            # 3. Generate a unique S3 key with date partitioning
            date_str = datetime.now().strftime("%Y-%m-%d")
            message_id = body.get("message_id", "unknown")
            s3_key = f"raw_surveys/date={date_str}/survey_{message_id}.json"

            # 4. Write to S3
            s3_client.put_object(
                Bucket=TARGET_BUCKET,
                Key=s3_key,
                Body=json.dumps(body),
                ContentType="application/json"
            )
            print(f"✅ Successfully wrote to S3: s3://{TARGET_BUCKET}/{s3_key}")

        except Exception as e:
            print(f"❌ Error processing record {record['messageId']}: {str(e)}")
            # Raising an exception here will cause SQS to retry the message
            
    return {
        'statusCode': 200,
        'body': json.dumps('Successfully processed SQS messages')
    }