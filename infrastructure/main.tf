terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ==========================================
# 1. S3 Buckets (Data Lake Raw Zone)
# ==========================================
resource "aws_s3_bucket" "raw_voter_files" {
  bucket = "civicpulse-raw-voter-files"

  tags = {
    Environment = "production"
    Project     = "CivicPulse"
  }
}

resource "aws_s3_bucket" "raw_surveys" {
  bucket = "civicpulse-raw-surveys"

  tags = {
    Environment = "production"
    Project     = "CivicPulse"
  }
}

# ==========================================
# 2. SQS Queue (Decoupled Ingestion)
# ==========================================
resource "aws_sqs_queue" "survey_queue" {
  name                       = "civicpulse-survey-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 86400 # 1 day

  tags = {
    Environment = "production"
    Project     = "CivicPulse"
  }
}

# ==========================================
# 3. Lambda Function & IAM (Serverless Processing)
# ==========================================
# Automatically zip the Lambda code from the local directory
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../ingestion/lambda_functions/sqs_to_s3_processor"
  output_path = "${path.module}/lambda_function.zip"
}

# IAM Role for Lambda with Least Privilege
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

# Attach least-privilege policy (SQS Read/Delete + S3 Write + CloudWatch Logs)
resource "aws_iam_role_policy" "lambda_s3_sqs_policy" {
  name = "civicpulse_lambda_s3_sqs_policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.survey_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.raw_surveys.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "sqs_processor" {
  function_name    = "civicpulse_sqs_to_s3_processor"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "python3.10"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TARGET_BUCKET = aws_s3_bucket.raw_surveys.bucket
    }
  }

  timeout     = 30
  memory_size = 128

  tags = {
    Environment = "production"
    Project     = "CivicPulse"
  }
}

# ==========================================
# 4. Event Source Mapping (SQS Trigger)
# ==========================================
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.survey_queue.arn
  function_name    = aws_lambda_function.sqs_processor.arn
  batch_size       = 10
}

# ==========================================
# 5. Outputs
# ==========================================
output "sqs_queue_url" {
  description = "The URL of the SQS queue for the microservice API to send messages to"
  value       = aws_sqs_queue.survey_queue.url
}

output "lambda_function_arn" {
  description = "The ARN of the deployed Lambda function"
  value       = aws_lambda_function.sqs_processor.arn
}