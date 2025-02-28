# main.tf - Main configuration file for AWS Warm Standby DR POC

# Provider configuration
provider "aws" {
  alias  = "primary"
  region = var.primary_region
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
}

# Variables
variable "primary_region" {
  description = "The primary AWS region"
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "The secondary AWS region for warm standby"
  default     = "us-west-2"
}

variable "application_name" {
  description = "Name of the application"
  default     = "warm-standby-poc"
}

variable "environment" {
  description = "Environment name"
  default     = "poc"
}

variable "primary_cidr" {
  description = "CIDR block for the primary VPC"
  default     = "10.0.0.0/16"
}

variable "secondary_cidr" {
  description = "CIDR block for the secondary VPC"
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "Number of availability zones to use in each region"
  default     = 2
}

variable "db_instance_class" {
  description = "Instance class for the Aurora database"
  default     = "db.r5.large"
}

variable "primary_min_capacity" {
  description = "Minimum number of instances in the primary region"
  default     = 2
}

variable "primary_max_capacity" {
  description = "Maximum number of instances in the primary region"
  default     = 4
}

variable "secondary_min_capacity" {
  description = "Minimum number of instances in the secondary region"
  default     = 1
}

variable "secondary_max_capacity" {
  description = "Maximum number of instances in the secondary region"
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type for application and frontend servers"
  default     = "t3.medium"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  default     = "example.com"
}

# Local values
locals {
  tags = {
    Application = var.application_name
    Environment = var.environment
    Terraform   = "true"
    DR_Strategy = "warm-standby"
  }
  
  primary_azs   = data.aws_availability_zones.primary.names
  secondary_azs = data.aws_availability_zones.secondary.names
}

# Data sources
data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

# Fetch latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux_primary" {
  provider    = aws.primary
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_ami" "amazon_linux_secondary" {
  provider    = aws.secondary
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}