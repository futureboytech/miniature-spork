# AWS Warm Standby Disaster Recovery POC

This repository contains Terraform infrastructure-as-code to deploy a Warm Standby Disaster Recovery solution on AWS.

## Architecture Overview

This solution implements a warm standby disaster recovery pattern with the following components:

1. **Multi-Region Setup**:
   - Primary region: us-east-1
   - Secondary (warm standby) region: us-west-2

2. **Networking**:
   - VPCs in both regions with public, private, database and intra subnets
   - Multi-AZ deployment for high availability
   - NAT Gateways for private subnet internet access

3. **Database**:
   - Aurora PostgreSQL Global Database spanning both regions
   - Automated snapshots with cross-region replication
   - Parameter groups optimized for PostgreSQL workloads

4. **Kubernetes**:
   - EKS clusters in both regions
   - Managed node groups scaled appropriately for each region
     - Primary region: min 2, max 4 nodes
     - Secondary region: min 1, max 2 nodes (warm standby)
   - Security groups for cluster communication

5. **Load Balancing**:
   - Application Load Balancers in both regions
   - Target groups configured for EKS applications
   - Health checks for monitoring application status

6. **Failover Routing**:
   - Route 53 DNS with failover routing policy
   - Health checks monitoring the primary region
   - Automatic traffic routing to secondary region upon failure

## Disaster Recovery Strategy

The warm standby architecture provides:

- **Low Recovery Time Objective (RTO)**: Secondary region is always running and immediately available
- **Low Recovery Point Objective (RPO)**: Aurora Global Database provides near-real-time replication
- **Cost Efficiency**: Secondary region runs with reduced capacity during normal operation
- **Automated Failover**: Route 53 automatically routes traffic to the secondary region
- **Backup Protection**: Multiple layers of snapshots for data protection

## Deployment

To deploy this infrastructure:

1. Configure AWS credentials for both regions
2. Update `terraform.tfvars` if needed
3. Run the Terraform workflow:

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

## Testing Disaster Recovery

The system includes a testing script to simulate disaster recovery scenarios:

```bash
bash iac/disaster-recovery-script.sh
```

This script provides options to:
- Check system status
- Simulate primary region failure
- Test database failover
- Restore primary region

## Architecture Diagram

```
                   ┌─────────────────┐                           ┌─────────────────┐
                   │   Route 53      │                           │   Route 53      │
                   │  Failover DNS   │                           │  Health Check   │
                   └────────┬────────┘                           └────────┬────────┘
                            │                                             │
                ┌───────────┴────────────┬──────────────────────┬─────────┴────────────┐
                │                        │                      │                       │
     ┌──────────▼───────────┐  ┌─────────▼──────────┐  ┌────────▼─────────────┐  ┌─────▼────────────────┐
     │  Primary Region      │  │   Primary VPC      │  │   Secondary Region   │  │   Secondary VPC      │
     │  (us-east-1)         │  │                    │  │   (us-west-2)        │  │                      │
     └──────────┬───────────┘  └─────────┬──────────┘  └────────┬─────────────┘  └─────┬────────────────┘
                │                         │                      │                       │
     ┌──────────▼───────────┐  ┌─────────▼──────────┐  ┌────────▼─────────────┐  ┌─────▼────────────────┐
     │  Application LB      │  │ EKS Cluster        │  │  Application LB      │  │ EKS Cluster          │
     │  (Public Facing)     │  │ (2-4 nodes)        │  │  (Public Facing)     │  │ (1-2 nodes)          │
     └──────────┬───────────┘  └─────────┬──────────┘  └────────┬─────────────┘  └─────┬────────────────┘
                │                         │                      │                       │
                │                         │                      │                       │
     ┌──────────▼───────────────────────┬─┴───┐        ┌────────▼───────────────────────┼────┐
     │                                  │     │        │                                 │    │
┌────▼───────┐ ┌─────────────────┐ ┌────▼───┐ │  ┌─────▼───────┐ ┌─────────────────┐ ┌──▼───┐
│ Aurora     │ │ Aurora          │ │ Target │ │  │ Aurora      │ │ Aurora          │ │Target│
│ Primary    │ │ Replicas        │ │ Groups │ │  │ Secondary   │ │ Replicas        │ │Groups│
│ Instance   │ │ (Multi-AZ)      │ │        │ │  │ Instance    │ │ (Multi-AZ)      │ │      │
└────┬───────┘ └─────────────────┘ └────────┘ │  └─────────────┘ └─────────────────┘ └──────┘
     │                                         │
     │                                         │
     │       ┌──────────────────────┐          │
     └───────┤  Aurora Global       ├──────────┘
             │  Database            │
             └──────────────────────┘
```

## Important Notes

- SSL certificates are commented out in the code. For production, add proper ACM certificates.
- The AWS Load Balancer Controller installation is commented out. For a complete solution, uncomment and complete this implementation.
- Modify the domain name in variables to match your actual domain.
