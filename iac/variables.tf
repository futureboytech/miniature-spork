# variables.tf - Variable declarations for the warm standby module

variable "primary_region" {
  description = "The primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "secondary_region" {
  description = "The secondary AWS region for warm standby"
  type        = string
  default     = "us-west-2"
}

variable "application_name" {
  description = "Name of the application"
  type        = string
  default     = "warm-standby-poc"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "poc"
}

variable "primary_cidr" {
  description = "CIDR block for the primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_cidr" {
  description = "CIDR block for the secondary VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "Number of availability zones to use in each region"
  type        = number
  default     = 2
  validation {
    condition     = var.availability_zones >= 2
    error_message = "At least 2 availability zones are required for high availability."
  }
}

variable "db_instance_class" {
  description = "Instance class for the Aurora database (legacy - use postgresql_instance_class instead)"
  type        = string
  default     = "db.r5.large"
}

variable "primary_min_capacity" {
  description = "Minimum number of instances in the primary region"
  type        = number
  default     = 2
}

variable "primary_max_capacity" {
  description = "Maximum number of instances in the primary region"
  type        = number
  default     = 4
}

variable "secondary_min_capacity" {
  description = "Minimum number of instances in the secondary region"
  type        = number
  default     = 1
}

variable "secondary_max_capacity" {
  description = "Maximum number of instances in the secondary region"
  type        = number
  default     = 2
}

variable "instance_type" {
  description = "EC2 instance type for application and frontend servers"
  type        = string
  default     = "t3.medium"
}

variable "domain_name" {
  description = "Domain name for Route 53"
  type        = string
  default     = "example.com"
}
