# db_utils.tf - PostgreSQL utilities and scripts for database management

# Create a Lambda function to initialize the PostgreSQL database
resource "aws_lambda_function" "db_init" {
  provider      = aws.primary
  function_name = "${var.application_name}-db-init"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs16.x"
  timeout       = 300
  
  filename      = data.archive_file.lambda_zip.output_path
  
  environment {
    variables = {
      DB_HOST     = aws_rds_cluster.primary.endpoint
      DB_PORT     = "5432"
      DB_NAME     = aws_rds_global_cluster.global.database_name
      DB_USERNAME = jsondecode(aws_secretsmanager_secret_version.db_password.secret_string)["username"]
      SECRET_ARN  = aws_secretsmanager_secret.db_password.arn
    }
  }
  
  vpc_config {
    subnet_ids         = module.vpc_primary.private_subnets
    security_group_ids = [aws_security_group.lambda_sg.id]
  }
  
  tags = local.tags
}

# Create a security group for the Lambda function
resource "aws_security_group" "lambda_sg" {
  provider    = aws.primary
  name        = "${var.application_name}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = module.vpc_primary.vpc_id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = local.tags
}

# Create a zip file for the Lambda function
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  
  source {
    content  = <<EOF
const { Client } = require('pg');
const AWS = require('aws-sdk');
const fs = require('fs');

exports.handler = async (event) => {
    // Get the DB password from Secrets Manager
    const secretsManager = new AWS.SecretsManager();
    const secretData = await secretsManager.getSecretValue({ SecretId: process.env.SECRET_ARN }).promise();
    const { password } = JSON.parse(secretData.SecretString);
    
    // Connect to the database
    const client = new Client({
        host: process.env.DB_HOST,
        port: process.env.DB_PORT,
        database: process.env.DB_NAME,
        user: process.env.DB_USERNAME,
        password: password,
    });
    
    try {
        await client.connect();
        console.log('Connected to the database');
        
        // Example SQL for creating a test table
        const sql = `
            -- Create a sample schema
            CREATE SCHEMA IF NOT EXISTS app;
            
            -- Create users table
            CREATE TABLE IF NOT EXISTS app.users (
                user_id SERIAL PRIMARY KEY,
                username VARCHAR(50) NOT NULL UNIQUE,
                email VARCHAR(100) NOT NULL UNIQUE,
                password_hash VARCHAR(255) NOT NULL,
                first_name VARCHAR(50),
                last_name VARCHAR(50),
                is_active BOOLEAN DEFAULT TRUE,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );
            
            -- Insert a test user if none exists
            INSERT INTO app.users (username, email, password_hash, first_name, last_name)
            VALUES ('testuser', 'test@example.com', 'hashed_password', 'Test', 'User')
            ON CONFLICT (username) DO NOTHING;
        `;
        
        await client.query(sql);
        console.log('Database initialized successfully');
        
        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Database initialized successfully' }),
        };
    } catch (error) {
        console.error('Error initializing database:', error);
        throw error;
    } finally {
        await client.end();
    }
};
EOF
    filename = "index.js"
  }
}

# Create an IAM role for the Lambda function
resource "aws_iam_role" "lambda_role" {
  provider = aws.primary
  name     = "${var.application_name}-lambda-role"
  
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
  
  tags = local.tags
}

# Attach policies to the Lambda role
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  provider   = aws.primary
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_secrets_access" {
  provider = aws.primary
  name     = "secrets-access"
  role     = aws_iam_role.lambda_role.name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Effect   = "Allow"
        Resource = aws_secretsmanager_secret.db_password.arn
      }
    ]
  })
}

# Create a CloudWatch Log Group for the Lambda function
resource "aws_cloudwatch_log_group" "lambda_logs" {
  provider          = aws.primary
  name              = "/aws/lambda/${aws_lambda_function.db_init.function_name}"
  retention_in_days = 30
  
  tags = local.tags
}

# Generate a local script file to connect to the PostgreSQL database
resource "local_file" "pg_connect_script" {
  filename = "${path.module}/scripts/connect_to_postgres.sh"
  content  = <<-EOF
    #!/bin/bash
    # Script to connect to the Aurora PostgreSQL database
    
    # Retrieve the master password from AWS Secrets Manager
    PASSWORD=$(aws secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.db_password.name} \
      --query 'SecretString' \
      --output text | jq -r '.password')
    
    # Connect to the primary database
    echo "Connecting to primary PostgreSQL database at ${aws_rds_cluster.primary.endpoint}..."
    PGPASSWORD=$PASSWORD psql \
      -h ${aws_rds_cluster.primary.endpoint} \
      -p 5432 \
      -U admin \
      -d ${aws_rds_global_cluster.global.database_name}
  EOF
  
  # Make the script executable
  provisioner "local-exec" {
    command = "chmod +x ${self.filename}"
  }
}

# Generate a script to load the schema into the database
resource "local_file" "pg_load_schema" {
  filename = "${path.module}/scripts/load_schema.sh"
  content  = <<-EOF
    #!/bin/bash
    # Script to load the schema into the PostgreSQL database
    
    # Retrieve the master password from AWS Secrets Manager
    PASSWORD=$(aws secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.db_password.name} \
      --query 'SecretString' \
      --output text | jq -r '.password')
    
    # Load the schema into the primary database
    echo "Loading schema into primary PostgreSQL database at ${aws_rds_cluster.primary.endpoint}..."
    PGPASSWORD=$PASSWORD psql \
      -h ${aws_rds_cluster.primary.endpoint} \
      -p 5432 \
      -U admin \
      -d ${aws_rds_global_cluster.global.database_name} \
      -f ${path.module}/scripts/initdb.sql
  EOF
  
  # Make the script executable
  provisioner "local-exec" {
    command = "chmod +x ${self.filename}"
  }
}

# Copy the PostgreSQL initialization script to the scripts directory
resource "local_file" "pg_init_script" {
  filename = "${path.module}/scripts/initdb.sql"
  content  = file("${path.module}/postgresql-migrations/initdb.sql")
}
