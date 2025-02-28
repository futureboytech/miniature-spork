# database.tf - Aurora database with global database setup

# Generate a random password for the Aurora database
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store the password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "db_password" {
  provider    = aws.primary
  name        = "${var.application_name}-db-password"
  description = "Password for Aurora database"
  
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  provider      = aws.primary
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.db_password.result
  })
}

# Global Aurora Cluster
resource "aws_rds_global_cluster" "global" {
  provider                     = aws.primary
  global_cluster_identifier    = "${var.application_name}-global-aurora-cluster"
  engine                       = "aurora-postgresql"
  engine_version               = "14.5"
  database_name                = "appdb"
  storage_encrypted            = true
  deletion_protection          = false
}

# Primary Region Aurora DB Cluster
resource "aws_rds_cluster" "primary" {
  provider                  = aws.primary
  cluster_identifier        = "${var.application_name}-primary-aurora-cluster"
  engine                    = aws_rds_global_cluster.global.engine
  engine_version            = aws_rds_global_cluster.global.engine_version
  database_name             = aws_rds_global_cluster.global.database_name
  master_username           = jsondecode(aws_secretsmanager_secret_version.db_password.secret_string)["username"]
  master_password           = jsondecode(aws_secretsmanager_secret_version.db_password.secret_string)["password"]
  backup_retention_period   = 30  # Increased from 7 to 30 days for better DR capability
  preferred_backup_window   = "03:00-05:00"  # Early morning window for backups
  db_subnet_group_name      = module.vpc_primary.database_subnet_group_name
  vpc_security_group_ids    = [aws_security_group.primary_db.id]
  skip_final_snapshot       = false  # Changed to false to ensure a final snapshot on deletion
  final_snapshot_identifier = "${var.application_name}-primary-final-snapshot"
  global_cluster_identifier = aws_rds_global_cluster.global.id
  
  # PostgreSQL specific configurations
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.postgresql.name
  port                            = 5432
  
  # Enable snapshot copying to the secondary region
  copy_tags_to_snapshot     = true
  
  # Enable automated backups
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  # Enable automatic minor version upgrades
  apply_immediately            = true
  allow_major_version_upgrade = false
  
  # Enable deletion protection for production (disable for POC)
  deletion_protection = false
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-aurora-cluster"
  })
}

# Primary Aurora DB Instances
resource "aws_rds_cluster_instance" "primary" {
  provider             = aws.primary
  count                = var.availability_zones
  identifier           = "${var.application_name}-primary-aurora-instance-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.primary.id
  instance_class       = var.postgresql_instance_class
  engine               = aws_rds_cluster.primary.engine
  engine_version       = aws_rds_cluster.primary.engine_version
  db_subnet_group_name = module.vpc_primary.database_subnet_group_name
  
  # PostgreSQL specific configurations
  db_parameter_group_name = aws_db_parameter_group.postgresql_instance.name
  
  # Enable auto minor version upgrades
  auto_minor_version_upgrade = true
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-aurora-instance-${count.index + 1}"
  })
}

# Secondary Region Aurora DB Cluster
resource "aws_rds_cluster" "secondary" {
  provider                  = aws.secondary
  cluster_identifier        = "${var.application_name}-secondary-aurora-cluster"
  engine                    = aws_rds_global_cluster.global.engine
  engine_version            = aws_rds_global_cluster.global.engine_version
  db_subnet_group_name      = module.vpc_secondary.database_subnet_group_name
  vpc_security_group_ids    = [aws_security_group.secondary_db.id]
  skip_final_snapshot       = false  # Changed to false to ensure a final snapshot on deletion
  final_snapshot_identifier = "${var.application_name}-secondary-final-snapshot"
  global_cluster_identifier = aws_rds_global_cluster.global.id
  
  # PostgreSQL specific configurations
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.postgresql_secondary.name
  port                            = 5432
  
  # Enable snapshot features
  backup_retention_period   = 14  # Maintain backups for secondary cluster as well
  preferred_backup_window   = "07:00-09:00"
  copy_tags_to_snapshot     = true
  
  # Enable logs for monitoring and troubleshooting
  enabled_cloudwatch_logs_exports = ["postgresql"]
  
  # For secondary cluster in a global database, these are set automatically
  source_region = var.primary_region
  
  # Must wait for the primary to be created first
  depends_on = [aws_rds_cluster_instance.primary]
  
  # Enable deletion protection for production (disable for POC)
  deletion_protection = false
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-secondary-aurora-cluster"
  })
}

# Secondary Aurora DB Instances
resource "aws_rds_cluster_instance" "secondary" {
  provider             = aws.secondary
  count                = var.availability_zones
  identifier           = "${var.application_name}-secondary-aurora-instance-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.secondary.id
  instance_class       = var.postgresql_instance_class
  engine               = aws_rds_cluster.secondary.engine
  engine_version       = aws_rds_cluster.secondary.engine_version
  db_subnet_group_name = module.vpc_secondary.database_subnet_group_name
  
  # PostgreSQL specific configurations
  db_parameter_group_name = aws_db_parameter_group.postgresql_instance_secondary.name
  
  # Enable auto minor version upgrades
  auto_minor_version_upgrade = true
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-secondary-aurora-instance-${count.index + 1}"
  })
}

# Create an Aurora DB snapshot for the primary cluster
resource "null_resource" "create_primary_snapshot" {
  # This will create a snapshot of the primary Aurora cluster
  
  # Only run this after the primary cluster is fully created
  depends_on = [aws_rds_cluster_instance.primary]
  
  # Use AWS CLI to take a snapshot
  provisioner "local-exec" {
    command = <<EOT
      aws rds create-db-cluster-snapshot \
        --db-cluster-identifier ${aws_rds_cluster.primary.id} \
        --db-cluster-snapshot-identifier ${var.application_name}-primary-snapshot \
        --region ${var.primary_region}
    EOT
  }
}

# Create an Aurora DB snapshot for the secondary cluster
resource "null_resource" "create_secondary_snapshot" {
  # This will create a snapshot of the secondary Aurora cluster
  # It corresponds to the "Aurora cluster Snapshot" shown in the diagram
  
  # Only run this after the secondary cluster is fully created
  depends_on = [aws_rds_cluster_instance.secondary]
  
  # Use AWS CLI to take a snapshot
  provisioner "local-exec" {
    command = <<EOT
      aws rds create-db-cluster-snapshot \
        --db-cluster-identifier ${aws_rds_cluster.secondary.id} \
        --db-cluster-snapshot-identifier ${var.application_name}-secondary-snapshot \
        --region ${var.secondary_region}
    EOT
  }
}

# Copy primary snapshot to secondary region for additional disaster recovery protection
resource "null_resource" "copy_snapshot_to_secondary" {
  # This will copy the primary cluster snapshot to the secondary region
  # for enhanced disaster recovery capabilities
  
  # Only run this after the primary snapshot is created
  depends_on = [null_resource.create_primary_snapshot]
  
  # Use AWS CLI to copy the snapshot to the secondary region
  provisioner "local-exec" {
    command = <<EOT
      # Wait for the snapshot to become available
      aws rds wait db-cluster-snapshot-available \
        --db-cluster-snapshot-identifier ${var.application_name}-primary-snapshot \
        --region ${var.primary_region}
      
      # Get the ARN of the source snapshot
      SOURCE_SNAPSHOT_ARN=$(aws rds describe-db-cluster-snapshots \
        --db-cluster-snapshot-identifier ${var.application_name}-primary-snapshot \
        --region ${var.primary_region} \
        --query 'DBClusterSnapshots[0].DBClusterSnapshotArn' \
        --output text)
      
      # Copy the snapshot to the secondary region
      aws rds copy-db-cluster-snapshot \
        --source-db-cluster-snapshot-identifier $SOURCE_SNAPSHOT_ARN \
        --target-db-cluster-snapshot-identifier ${var.application_name}-primary-snapshot-copy \
        --kms-key-id alias/aws/rds \
        --region ${var.secondary_region}
    EOT
  }
}
