# vpc.tf - VPC configurations for primary and secondary regions

# Primary Region VPC
module "vpc_primary" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"
  providers = {
    aws = aws.primary
  }

  name = "${var.application_name}-primary-vpc"
  cidr = var.primary_cidr

  # Create subnets in all available AZs (up to the specified number)
  azs                 = slice(local.primary_azs, 0, var.availability_zones)
  private_subnets     = [for i in range(var.availability_zones) : cidrsubnet(var.primary_cidr, 8, i)]
  public_subnets      = [for i in range(var.availability_zones) : cidrsubnet(var.primary_cidr, 8, i + var.availability_zones)]
  database_subnets    = [for i in range(var.availability_zones) : cidrsubnet(var.primary_cidr, 8, i + var.availability_zones * 2)]
  
  # For EKS - create a dedicated set of subnets
  intra_subnets       = [for i in range(var.availability_zones) : cidrsubnet(var.primary_cidr, 8, i + var.availability_zones * 3)]

  # Enable NAT Gateways for private subnet internet access
  enable_nat_gateway = true
  single_nat_gateway = false  # Use multiple NAT gateways for high availability
  
  # Create a dedicated subnet group for Aurora
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  
  # Enable DNS support
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs for network monitoring (optional)
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  # Public subnet - map public IP on launch
  map_public_ip_on_launch = true

  # Add specific tags required for Kubernetes
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.application_name}-primary-eks" = "shared"
    "kubernetes.io/role/elb"                                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.application_name}-primary-eks" = "shared"
    "kubernetes.io/role/internal-elb"                           = "1"
  }

  tags = local.tags
}

# Secondary Region VPC
module "vpc_secondary" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"
  providers = {
    aws = aws.secondary
  }

  name = "${var.application_name}-secondary-vpc"
  cidr = var.secondary_cidr

  # Create subnets in all available AZs (up to the specified number)
  azs                 = slice(local.secondary_azs, 0, var.availability_zones)
  private_subnets     = [for i in range(var.availability_zones) : cidrsubnet(var.secondary_cidr, 8, i)]
  public_subnets      = [for i in range(var.availability_zones) : cidrsubnet(var.secondary_cidr, 8, i + var.availability_zones)]
  database_subnets    = [for i in range(var.availability_zones) : cidrsubnet(var.secondary_cidr, 8, i + var.availability_zones * 2)]
  
  # For EKS - create a dedicated set of subnets
  intra_subnets       = [for i in range(var.availability_zones) : cidrsubnet(var.secondary_cidr, 8, i + var.availability_zones * 3)]

  # Enable NAT Gateways for private subnet internet access
  enable_nat_gateway = true
  single_nat_gateway = false  # Use multiple NAT gateways for high availability
  
  # Create a dedicated subnet group for Aurora
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  
  # Enable DNS support
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs for network monitoring (optional)
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  # Public subnet - map public IP on launch
  map_public_ip_on_launch = true

  # Add specific tags required for Kubernetes
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.application_name}-secondary-eks" = "shared"
    "kubernetes.io/role/elb"                                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.application_name}-secondary-eks" = "shared"
    "kubernetes.io/role/internal-elb"                             = "1"
  }

  tags = local.tags
}