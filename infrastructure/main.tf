terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. S3 Buckets
resource "aws_s3_bucket" "raw_voter_files" {
  bucket = "civicpulse-raw-voter-files"
}

resource "aws_s3_bucket" "raw_surveys" {
  bucket = "civicpulse-raw-surveys"
}

# 2. SQS Queue
resource "aws_sqs_queue" "survey_queue" {
  name                       = "civicpulse-survey-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400
}

# 3. IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "civicpulse_lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Attach S3 write and SQS read policies to Lambda
resource "aws_iam_role_policy" "lambda_sqs_s3_permissions" {
  name = "civicpulse_lambda_sqs_s3_permissions"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Permission to write processed data to S3
        Action   = ["s3:PutObject"]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.raw_surveys.arn}/*"
      },
      {
        # Permission to read and manage messages from the SQS queue
        Action   = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.survey_queue.arn
      }
    ]
  })
}

# 4. Lambda Function
# Note: In a real CI/CD pipeline, you would zip this code and upload it. 
# For local dev, we point to the directory.
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../ingestion/lambda_functions/sqs_to_s3_processor"
  output_path = "lambda_function_payload.zip"
}

resource "aws_lambda_function" "sqs_processor" {
  filename      = "lambda_function_payload.zip"
  function_name = "civicpulse_sqs_to_s3_processor"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "index.lambda_handler"
  runtime       = "python3.9"

  environment {
    variables = {
      TARGET_BUCKET = aws_s3_bucket.raw_surveys.bucket
    }
  }

  depends_on = [data.archive_file.lambda_zip]
}

# 5. SQS Event Source Mapping (Triggers Lambda when messages arrive)
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.survey_queue.arn
  function_name    = aws_lambda_function.sqs_processor.arn
  batch_size       = 10
}

# Outputs
output "sqs_queue_url" {
  value = aws_sqs_queue.survey_queue.url
}