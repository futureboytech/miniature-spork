#!/bin/bash
# dr_simulate.sh - Script to simulate disaster scenarios and test recovery for Aurora PostgreSQL

set -e

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load configuration from Terraform outputs
echo -e "${BLUE}Loading configuration from Terraform outputs...${NC}"
PRIMARY_REGION=$(terraform output -raw primary_region)
SECONDARY_REGION=$(terraform output -raw secondary_region)
APP_URL=$(terraform output -raw application_url)
PRIMARY_ALB=$(terraform output -raw primary_alb_dns_name)
SECONDARY_ALB=$(terraform output -raw secondary_alb_dns_name)
PRIMARY_FRONTEND_ASG=$(terraform output -raw primary_frontend_asg_name)
PRIMARY_APP_ASG=$(terraform output -raw primary_app_asg_name)
GLOBAL_CLUSTER_ID=$(terraform output -raw global_cluster_id)
PRIMARY_DB_ENDPOINT=$(terraform output -raw primary_aurora_endpoint)
SECONDARY_DB_ENDPOINT=$(terraform output -raw secondary_aurora_endpoint)
PRIMARY_HEALTH_CHECK=$(terraform output -raw route53_health_check_primary_id)

echo -e "${GREEN}Configuration loaded successfully!${NC}"
echo -e "Primary Region: ${PRIMARY_REGION}"
echo -e "Secondary Region: ${SECONDARY_REGION}"
echo -e "Application URL: ${APP_URL}"
echo -e "Global DB Cluster: ${GLOBAL_CLUSTER_ID}"

# Function to check current status
check_status() {
    echo -e "\n${BLUE}=== Current System Status ===${NC}"
    
    # Check Route53 health checks
    echo -e "\n${YELLOW}Route53 Health Check Status:${NC}"
    aws route53 get-health-check-status \
        --health-check-id ${PRIMARY_HEALTH_CHECK} \
        --region us-east-1 \
        --query 'HealthCheckObservations[].StatusReport.Status' \
        --output text
    
    # Check primary region ALB
    echo -e "\n${YELLOW}Primary ALB Status:${NC}"
    aws elbv2 describe-target-health \
        --target-group-arn $(aws elbv2 describe-target-groups \
            --names warm-standby-poc-primary-frontend-tg \
            --region ${PRIMARY_REGION} \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text) \
        --region ${PRIMARY_REGION} \
        --query 'TargetHealthDescriptions[].TargetHealth.State' \
        --output text
    
    # Check current DNS resolution
    echo -e "\n${YELLOW}Current DNS Resolution:${NC}"
    dig +short ${APP_URL}
    
    # Check Aurora status
    echo -e "\n${YELLOW}Aurora DB Status:${NC}"
    echo -e "Primary Cluster:"
    aws rds describe-db-clusters \
        --db-cluster-identifier $(echo ${PRIMARY_DB_ENDPOINT} | cut -d'.' -f1) \
        --region ${PRIMARY_REGION} \
        --query 'DBClusters[0].Status' \
        --output text
    
    echo -e "Secondary Cluster:"
    aws rds describe-db-clusters \
        --db-cluster-identifier $(echo ${SECONDARY_DB_ENDPOINT} | cut -d'.' -f1) \
        --region ${SECONDARY_REGION} \
        --query 'DBClusters[0].Status' \
        --output text
        
    # Check Aurora snapshot status
    echo -e "\n${YELLOW}Aurora DB Snapshots:${NC}"
    echo -e "Primary Region Snapshots:"
    aws rds describe-db-cluster-snapshots \
        --db-cluster-identifier $(echo ${PRIMARY_DB_ENDPOINT} | cut -d'.' -f1) \
        --region ${PRIMARY_REGION} \
        --query 'DBClusterSnapshots[0:3].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
        --output table
    
    echo -e "Secondary Region Snapshots:"
    aws rds describe-db-cluster-snapshots \
        --db-cluster-identifier $(echo ${SECONDARY_DB_ENDPOINT} | cut -d'.' -f1) \
        --region ${SECONDARY_REGION} \
        --query 'DBClusterSnapshots[0:3].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
        --output table
        
    # Check for copied snapshots in secondary region
    echo -e "Cross-Region Snapshot Copies in Secondary Region:"
    aws rds describe-db-cluster-snapshots \
        --snapshot-type manual \
        --region ${SECONDARY_REGION} \
        --query 'DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, `primary`) == `true`].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
        --output table
}

# Function to simulate region failure
simulate_region_failure() {
    echo -e "\n${RED}=== Simulating Primary Region Failure ===${NC}"
    echo -e "${YELLOW}This will suspend the primary region's Auto Scaling Groups${NC}"
    
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Simulation cancelled.${NC}"
        return
    fi
    
    # Suspend Auto Scaling processes in the primary region
    echo -e "${YELLOW}Suspending Auto Scaling processes in primary region...${NC}"
    aws autoscaling suspend-processes \
        --auto-scaling-group-name ${PRIMARY_FRONTEND_ASG} \
        --scaling-processes AlarmNotification AddToLoadBalancer HealthCheck Launch Terminate \
        --region ${PRIMARY_REGION}
    
    aws autoscaling suspend-processes \
        --auto-scaling-group-name ${PRIMARY_APP_ASG} \
        --scaling-processes AlarmNotification HealthCheck Launch Terminate \
        --region ${PRIMARY_REGION}
    
    # Detach instances from load balancer
    echo -e "${YELLOW}Detaching instances from load balancer...${NC}"
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
        --names warm-standby-poc-primary-frontend-tg \
        --region ${PRIMARY_REGION} \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    TARGETS=$(aws elbv2 describe-target-health \
        --target-group-arn ${TARGET_GROUP_ARN} \
        --region ${PRIMARY_REGION} \
        --query 'TargetHealthDescriptions[].Target.Id' \
        --output text)
    
    for TARGET in ${TARGETS}; do
        aws elbv2 deregister-targets \
            --target-group-arn ${TARGET_GROUP_ARN} \
            --targets Id=${TARGET} \
            --region ${PRIMARY_REGION}
    done
    
    echo -e "${GREEN}Primary region simulated failure complete.${NC}"
    echo -e "${YELLOW}Waiting for Route53 to detect failure and failover (may take 1-2 minutes)...${NC}"
    
    # Wait for Route53 to detect failure
    sleep 60
    
    # Check status after failure
    check_status
    
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${YELLOW}Failover should now be in progress.${NC}"
    echo -e "${YELLOW}You can verify by:${NC}"
    echo -e "1. Checking that DNS now resolves to the secondary region"
    echo -e "2. Testing that the application remains accessible"
    echo -e "3. Monitoring CloudWatch dashboard for changes"
    echo -e "${BLUE}============================================${NC}"
}

# Function to restore primary region
restore_primary_region() {
    echo -e "\n${GREEN}=== Restoring Primary Region ===${NC}"
    
    read -p "Are you sure you want to restore the primary region? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Restoration cancelled.${NC}"
        return
    fi
    
    # Resume Auto Scaling processes in the primary region
    echo -e "${YELLOW}Resuming Auto Scaling processes in primary region...${NC}"
    aws autoscaling resume-processes \
        --auto-scaling-group-name ${PRIMARY_FRONTEND_ASG} \
        --region ${PRIMARY_REGION}
    
    aws autoscaling resume-processes \
        --auto-scaling-group-name ${PRIMARY_APP_ASG} \
        --region ${PRIMARY_REGION}
    
    # Wait for instances to be healthy
    echo -e "${YELLOW}Waiting for instances to become healthy...${NC}"
    sleep 60
    
    # Get the instances from the Auto Scaling Group
    INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names ${PRIMARY_FRONTEND_ASG} \
        --region ${PRIMARY_REGION} \
        --query 'AutoScalingGroups[0].Instances[].InstanceId' \
        --output text)
    
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
        --names warm-standby-poc-primary-frontend-tg \
        --region ${PRIMARY_REGION} \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Re-register each instance with the target group
    echo -e "${YELLOW}Registering instances with load balancer...${NC}"
    for INSTANCE_ID in ${INSTANCE_IDS}; do
        aws elbv2 register-targets \
            --target-group-arn ${TARGET_GROUP_ARN} \
            --targets Id=${INSTANCE_ID} \
            --region ${PRIMARY_REGION}
    done
    
    echo -e "${GREEN}Primary region restoration initiated.${NC}"
    echo -e "${YELLOW}Waiting for Route53 to detect recovery (may take 1-2 minutes)...${NC}"
    
    # Wait for Route53 to detect recovery
    sleep 60
    
    # Check status after recovery
    check_status
    
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${GREEN}Primary region should now be restored.${NC}"
    echo -e "${YELLOW}You can verify by:${NC}"
    echo -e "1. Checking that DNS is routing back to the primary region"
    echo -e "2. Testing that the application is served from the primary region"
    echo -e "${BLUE}============================================${NC}"
}

# Function to test Aurora database failover
test_aurora_failover() {
    echo -e "\n${BLUE}=== Testing Aurora Global Database Failover ===${NC}"
    
    read -p "Are you sure you want to failover the Aurora database to the secondary region? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Database failover test cancelled.${NC}"
        return
    fi
    
    # Get the ARN of the secondary cluster
    SECONDARY_CLUSTER_ARN=$(aws rds describe-db-clusters \
        --db-cluster-identifier $(echo ${SECONDARY_DB_ENDPOINT} | cut -d'.' -f1) \
        --region ${SECONDARY_REGION} \
        --query 'DBClusters[0].DBClusterArn' \
        --output text)
    
    # Execute the failover
    echo -e "${YELLOW}Initiating Aurora Global Database failover...${NC}"
    aws rds failover-global-cluster \
        --global-cluster-identifier ${GLOBAL_CLUSTER_ID} \
        --target-db-cluster-identifier ${SECONDARY_CLUSTER_ARN} \
        --region ${PRIMARY_REGION}
    
    echo -e "${YELLOW}Failover initiated. This process may take several minutes...${NC}"
    echo -e "${YELLOW}Monitoring database status...${NC}"
    
    # Monitor failover progress
    for i in {1..6}; do
        echo -e "\n${YELLOW}Check $i:${NC}"
        
        PRIMARY_STATUS=$(aws rds describe-db-clusters \
            --db-cluster-identifier $(echo ${PRIMARY_DB_ENDPOINT} | cut -d'.' -f1) \
            --region ${PRIMARY_REGION} \
            --query 'DBClusters[0].Status' \
            --output text)
            
        SECONDARY_STATUS=$(aws rds describe-db-clusters \
            --db-cluster-identifier $(echo ${SECONDARY_DB_ENDPOINT} | cut -d'.' -f1) \
            --region ${SECONDARY_REGION} \
            --query 'DBClusters[0].Status' \
            --output text)
            
        echo "Primary: ${PRIMARY_STATUS}, Secondary: ${SECONDARY_STATUS}"
        
        if [ "${SECONDARY_STATUS}" == "available" ]; then
            echo -e "${GREEN}Secondary cluster is now available as the primary!${NC}"
            break
        fi
        
        echo -e "${YELLOW}Waiting 30 seconds for next check...${NC}"
        sleep 30
    done
    
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${GREEN}Aurora failover test complete.${NC}"
    echo -e "${YELLOW}Important:${NC}"
    echo -e "1. The secondary cluster is now the primary writer"
    echo -e "2. Applications should be reconfigured to use the new endpoint"
    echo -e "3. To failback, run this test again but target the original primary"
    echo -e "${BLUE}============================================${NC}"
}

# Function to manage Aurora snapshots
manage_snapshots() {
    echo -e "\n${BLUE}=== Aurora DB Snapshot Management ===${NC}"
    
    # Show snapshot submenu
    echo -e "1. ${YELLOW}Create Primary DB Snapshot${NC}"
    echo -e "2. ${YELLOW}Copy Primary Snapshot to Secondary Region${NC}"
    echo -e "3. ${YELLOW}List Available Snapshots${NC}"
    echo -e "4. ${YELLOW}Restore from Snapshot (Test)${NC}"
    echo -e "5. ${GREEN}Back to Main Menu${NC}"
    
    read -p "Select an option (1-5): " snapshot_option
    
    case $snapshot_option in
        1)
            # Create a new snapshot of the primary cluster
            echo -e "\n${YELLOW}Creating a new snapshot of the primary DB cluster...${NC}"
            SNAPSHOT_ID="${var.application_name}-primary-manual-$(date +%Y%m%d%H%M)"
            
            aws rds create-db-cluster-snapshot \
                --db-cluster-identifier $(echo ${PRIMARY_DB_ENDPOINT} | cut -d'.' -f1) \
                --db-cluster-snapshot-identifier ${SNAPSHOT_ID} \
                --region ${PRIMARY_REGION}
                
            echo -e "${GREEN}Snapshot creation initiated with ID: ${SNAPSHOT_ID}${NC}"
            echo -e "${YELLOW}Waiting for snapshot to become available...${NC}"
            
            aws rds wait db-cluster-snapshot-available \
                --db-cluster-snapshot-identifier ${SNAPSHOT_ID} \
                --region ${PRIMARY_REGION}
                
            echo -e "${GREEN}Snapshot ${SNAPSHOT_ID} is now available.${NC}"
            press_enter_to_continue; manage_snapshots ;;
            
        2)
            # Copy a snapshot to the secondary region
            echo -e "\n${YELLOW}Available primary region snapshots:${NC}"
            aws rds describe-db-cluster-snapshots \
                --db-cluster-identifier $(echo ${PRIMARY_DB_ENDPOINT} | cut -d'.' -f1) \
                --region ${PRIMARY_REGION} \
                --query 'DBClusterSnapshots[0:5].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
                --output table
                
            read -p "Enter the snapshot ID to copy to the secondary region: " SOURCE_SNAPSHOT_ID
            TARGET_SNAPSHOT_ID="${SOURCE_SNAPSHOT_ID}-copy"
            
            # Get the ARN of the source snapshot
            SOURCE_SNAPSHOT_ARN=$(aws rds describe-db-cluster-snapshots \
                --db-cluster-snapshot-identifier ${SOURCE_SNAPSHOT_ID} \
                --region ${PRIMARY_REGION} \
                --query 'DBClusterSnapshots[0].DBClusterSnapshotArn' \
                --output text)
                
            # Copy the snapshot to the secondary region
            echo -e "${YELLOW}Copying snapshot to secondary region...${NC}"
            aws rds copy-db-cluster-snapshot \
                --source-db-cluster-snapshot-identifier ${SOURCE_SNAPSHOT_ARN} \
                --target-db-cluster-snapshot-identifier ${TARGET_SNAPSHOT_ID} \
                --kms-key-id alias/aws/rds \
                --region ${SECONDARY_REGION}
                
            echo -e "${GREEN}Snapshot copy initiated. Target ID: ${TARGET_SNAPSHOT_ID}${NC}"
            echo -e "${YELLOW}This process may take some time to complete.${NC}"
            press_enter_to_continue; manage_snapshots ;;
            
        3)
            # List available snapshots in both regions
            echo -e "\n${YELLOW}Primary Region Snapshots:${NC}"
            aws rds describe-db-cluster-snapshots \
                --db-cluster-identifier $(echo ${PRIMARY_DB_ENDPOINT} | cut -d'.' -f1) \
                --region ${PRIMARY_REGION} \
                --query 'DBClusterSnapshots[0:10].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
                --output table
                
            echo -e "\n${YELLOW}Secondary Region Snapshots:${NC}"
            aws rds describe-db-cluster-snapshots \
                --db-cluster-identifier $(echo ${SECONDARY_DB_ENDPOINT} | cut -d'.' -f1) \
                --region ${SECONDARY_REGION} \
                --query 'DBClusterSnapshots[0:5].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
                --output table
                
            echo -e "\n${YELLOW}Copied Snapshots in Secondary Region:${NC}"
            aws rds describe-db-cluster-snapshots \
                --snapshot-type manual \
                --region ${SECONDARY_REGION} \
                --query 'DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, `copy`) == `true`].[DBClusterSnapshotIdentifier,SnapshotCreateTime,Status]' \
                --output table
                
            press_enter_to_continue; manage_snapshots ;;
            
        4)
            # Note: This is a demonstration only and would require more complex implementation
            # for an actual restore operation in a production environment
            echo -e "\n${RED}WARNING: This is a demonstration of how to restore from a snapshot.${NC}"
            echo -e "${RED}In a real environment, this would create a new DB cluster from the snapshot.${NC}"
            echo -e "${YELLOW}Example restore command:${NC}"
            echo -e "aws rds restore-db-cluster-from-snapshot \\"
            echo -e "  --db-cluster-identifier [new-cluster-name] \\"
            echo -e "  --snapshot-identifier [snapshot-id] \\"
            echo -e "  --engine aurora-mysql \\"
            echo -e "  --region [region]"
            press_enter_to_continue; manage_snapshots ;;
            
        5)
            main_menu ;;
            
        *)
            echo -e "${RED}Invalid option. Please try again.${NC}"
            press_enter_to_continue; manage_snapshots ;;
    esac
}

# Main menu
main_menu() {
    clear
    echo -e "${BLUE}====== Warm Standby Disaster Recovery Testing ======${NC}"
    echo -e "1. ${YELLOW}Check Current Status${NC}"
    echo -e "2. ${RED}Simulate Primary Region Failure${NC}"
    echo -e "3. ${GREEN}Restore Primary Region${NC}"
    echo -e "4. ${YELLOW}Test Aurora Database Failover${NC}"
    echo -e "5. ${BLUE}Manage Aurora Snapshots${NC}"
    echo -e "6. ${RED}Exit${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    read -p "Select an option (1-6): " option
    
    case $option in
        1) check_status; press_enter_to_continue; main_menu ;;
        2) simulate_region_failure; press_enter_to_continue; main_menu ;;
        3) restore_primary_region; press_enter_to_continue; main_menu ;;
        4) test_aurora_failover; press_enter_to_continue; main_menu ;;
        5) manage_snapshots ;;
        6) echo -e "${GREEN}Exiting.${NC}"; exit 0 ;;
        *) echo -e "${RED}Invalid option. Please try again.${NC}"; press_enter_to_continue; main_menu ;;
    esac
}

press_enter_to_continue() {
    echo
    read -p "Press Enter to continue..."
}

# Start the script
main_menu
