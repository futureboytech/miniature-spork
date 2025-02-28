# CloudWatch Event Rule to monitor snapshot creation
resource "aws_cloudwatch_event_rule" "snapshot_created" {
  provider    = aws.primary
  name        = "${var.application_name}-snapshot-created"
  description = "Capture Aurora PostgreSQL snapshot creation events"
  
  event_pattern = jsonencode({
    source      = ["aws.rds"],
    detail-type = ["RDS DB Cluster Snapshot Event"],
    detail      = {
      EventCategories = ["creation"],
      SourceType      = ["CLUSTER_SNAPSHOT"],
      SourceArn       = [aws_rds_cluster.primary.arn]
    }
  })
  
  tags = local.tags
}