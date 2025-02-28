# AWS Warm Standby Disaster Recovery Proof of Concept

This Terraform module implements a warm standby disaster recovery pattern on AWS, as illustrated in the reference architecture diagram. The warm standby approach ensures a scaled-down but fully functional copy of your production environment is always running in a secondary region, ready to take over traffic with minimal downtime in case of a disaster.

## Architecture Overview

This implementation creates the following resources:

### Primary Region

- VPC with public and private subnets across multiple Availability Zones
- Application Load Balancer (ALB) in public subnets
- Auto Scaling Groups for frontend and application servers in private subnets
- Aurora MySQL primary cluster
- Security groups for all components
- CloudWatch alarms and monitoring
- Route 53 health checks

### Secondary Region

- VPC with public and private subnets across multiple Availability Zones
- Application Load Balancer (ALB) in public subnets
- Auto Scaling Groups for frontend and application servers in private subnets (scaled-down)
- Aurora MySQL replica cluster
- Security groups for all components
- CloudWatch alarms and monitoring
- Route 53 health checks

### Global Resources

- Route 53 DNS records with failover routing policy
- Aurora PostgreSQL Global Database for cross-region replication
- CloudWatch dashboard to monitor both regions

## Key Disaster Recovery Features

1. **Multi-AZ Deployment**: All resources are deployed across multiple Availability Zones for high availability within each region.

2. **Cross-Region Replication**: Aurora Global Database provides asynchronous replication between regions with minimal latency.

3. **Automated Failover**: Route 53 health checks monitor the primary region and automatically route traffic to the secondary region if issues are detected.

4. **Scaled-Down Secondary Environment**: The secondary region runs with fewer instances to optimize costs while still being capable of handling traffic immediately.

5. **Database Snapshots**: The solution includes comprehensive Aurora DB snapshot management with:
   - Automated daily, weekly, and monthly snapshots of the primary Aurora cluster
   - Cross-region snapshot replication to the secondary region
   - Manual snapshot capabilities with the disaster recovery testing toolkit
   - Backup lifecycle management with different retention periods for different snapshot frequencies

## Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform 1.0.0 or later
- A registered domain name (for Route 53 configuration)
- AWS account access to both primary and secondary regions

## Usage

1. Clone this repository to your local machine.

2. Update the `terraform.tfvars` file with your specific configurations:

```hcl
# AWS regions for deployment
primary_region         = "us-east-1"
secondary_region       = "us-west-2"

# Application configuration
application_name       = "your-app-name"
environment            = "prod"

# Network configuration
primary_cidr           = "10.0.0.0/16"
secondary_cidr         = "10.1.0.0/16"
availability_zones     = 2

# Compute configuration
primary_min_capacity   = 2
primary_max_capacity   = 4
secondary_min_capacity = 1
secondary_max_capacity = 2
instance_type          = "t3.medium"

# DNS configuration
domain_name            = "yourdomain.com"  # Replace with your actual domain
```

3. Initialize Terraform:

```bash
terraform init
```

4. Review the execution plan:

```bash
terraform plan
```

5. Apply the configuration:

```bash
terraform apply
```

6. After successful deployment, Terraform will output the key resource identifiers and endpoints.

## Testing Failover

To test the failover capabilities of your warm standby setup:

1. **Manual Failover Testing**:
   - Access the application using the Route 53 domain name (e.g., app.yourdomain.com)
   - Temporarily disable the primary region's load balancer or instances
   - Observe that traffic is automatically routed to the secondary region

2. **Database Failover Testing**:
   - You can initiate a manual failover of the Aurora Global Database using the AWS Console or CLI:

```bash
aws rds failover-global-cluster \
    --global-cluster-identifier <your-global-cluster-id> \
    --target-db-cluster-identifier <your-secondary-cluster-arn>
```

3. **Simulated Region Failure**:
   - In a controlled testing environment, you can modify the Route 53 health check to temporarily fail
   - Observe the traffic shifting to the secondary region

## Monitoring

The deployment includes a CloudWatch dashboard that provides a unified view of metrics from both regions, including:

- Load balancer request counts and latency
- Auto Scaling Group instance counts
- Aurora database metrics
- Route 53 health check status

You can access this dashboard from the CloudWatch console in the primary region.

## Clean Up

To destroy all resources created by this Terraform configuration:

```bash
terraform destroy
```

## Considerations for Production Use

This proof of concept demonstrates the core components of a warm standby disaster recovery strategy. For production use, consider these enhancements:

1. **Secrets Management**: Implement a more robust secrets management solution using AWS Secrets Manager rotation or integration with a dedicated secrets management service.

2. **Encryption**: Enable encryption for all data at rest and in transit.

3. **IAM Roles**: Implement more granular IAM policies following the principle of least privilege.

4. **Monitoring and Alerting**: Expand CloudWatch alarms and set up notifications via SNS to alert operations teams.

5. **Data Replication Validation**: Implement checks to validate data consistency between regions.

6. **Automated Testing**: Set up regular automated failover testing in a non-production environment.

7. **Cost Optimization**: Analyze usage patterns to optimize instance sizes and scaling policies.

8. **Documentation**: Develop detailed runbooks for failover and recovery procedures.

## Difference Between Pilot Light and Warm Standby

As mentioned in the requirements, it's important to understand the distinction between pilot light and warm standby approaches:

- **Pilot Light**: Core infrastructure is provisioned in the secondary region, but it cannot process requests without additional action (like scaling up resources or activating systems).

- **Warm Standby**: A scaled-down but fully functional environment is always running in the secondary region and can immediately process requests, albeit at reduced capacity.

This implementation uses the warm standby approach with minimal resources running in the secondary region, but capable of immediately handling traffic if the primary region fails.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
