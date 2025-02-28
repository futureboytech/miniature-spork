# PostgreSQL-specific parameters for Aurora configuration

variable "postgresql_engine_version" {
  description = "The version of PostgreSQL engine to use for Aurora"
  type        = string
  default     = "14.5"
}

variable "postgresql_parameter_group_family" {
  description = "Parameter group family for PostgreSQL"
  type        = string
  default     = "aurora-postgresql14"
}

variable "postgresql_instance_class" {
  description = "Instance class for PostgreSQL clusters"
  type        = string
  default     = "db.r5.large"
}

# PostgreSQL parameter group
resource "aws_rds_cluster_parameter_group" "postgresql" {
  provider    = aws.primary
  name        = "${var.application_name}-postgresql-params"
  family      = var.postgresql_parameter_group_family
  description = "Parameter group for Aurora PostgreSQL cluster"

  # Common PostgreSQL optimization parameters
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/32768}MB"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "max_connections"
    value = "LEAST({DBInstanceClassMemory/9531392},5000)"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "work_mem"
    value = "16384"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "1048576"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries taking more than 1 second
    apply_method = "pending-reboot"
  }

  tags = local.tags
}

# PostgreSQL DB parameter group for instances
resource "aws_db_parameter_group" "postgresql_instance" {
  provider    = aws.primary
  name        = "${var.application_name}-postgresql-instance-params"
  family      = var.postgresql_parameter_group_family
  description = "Parameter group for Aurora PostgreSQL instances"

  tags = local.tags
}

# Secondary region parameters
resource "aws_rds_cluster_parameter_group" "postgresql_secondary" {
  provider    = aws.secondary
  name        = "${var.application_name}-postgresql-params-secondary"
  family      = var.postgresql_parameter_group_family
  description = "Parameter group for Aurora PostgreSQL cluster in secondary region"

  # Same parameters as primary region
  parameter {
    name  = "shared_buffers"
    value = "{DBInstanceClassMemory/32768}MB"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "max_connections"
    value = "LEAST({DBInstanceClassMemory/9531392},5000)"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "work_mem"
    value = "16384"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "maintenance_work_mem"
    value = "1048576"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "random_page_cost"
    value = "1.1"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"  # Log queries taking more than 1 second
    apply_method = "pending-reboot"
  }

  tags = local.tags
}

resource "aws_db_parameter_group" "postgresql_instance_secondary" {
  provider    = aws.secondary
  name        = "${var.application_name}-postgresql-instance-params-secondary"
  family      = var.postgresql_parameter_group_family
  description = "Parameter group for Aurora PostgreSQL instances in secondary region"

  tags = local.tags
}
