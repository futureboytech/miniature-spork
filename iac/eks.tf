# eks.tf - EKS configurations for primary and secondary regions

# EKS-specific variables
variable "primary_eks_node_group_min" {
  description = "Minimum number of nodes in primary EKS node group"
  type        = number
  default     = 2
}

variable "primary_eks_node_group_max" {
  description = "Maximum number of nodes in primary EKS node group"
  type        = number
  default     = 4
}

variable "primary_eks_node_group_desired" {
  description = "Desired number of nodes in primary EKS node group"
  type        = number
  default     = 2
}

variable "secondary_eks_node_group_min" {
  description = "Minimum number of nodes in secondary EKS node group"
  type        = number
  default     = 1
}

variable "secondary_eks_node_group_max" {
  description = "Maximum number of nodes in secondary EKS node group"
  type        = number
  default     = 2
}

variable "secondary_eks_node_group_desired" {
  description = "Desired number of nodes in secondary EKS node group"
  type        = number
  default     = 1
}

variable "eks_node_instance_type" {
  description = "Instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.24"
}

# Primary Region EKS Cluster
module "eks_primary" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"
  providers = {
    aws = aws.primary
  }

  cluster_name                   = "${var.application_name}-primary-eks"
  cluster_version                = var.eks_version
  cluster_endpoint_public_access = true
  
  vpc_id     = module.vpc_primary.vpc_id
  subnet_ids = module.vpc_primary.private_subnets

  # Add security groups
  cluster_security_group_additional_rules = {
    egress_all = {
      description = "Allow all outbound traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Enable EKS managed add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Managed node groups
  eks_managed_node_group_defaults = {
    ami_type               = "AL2_x86_64"
    disk_size              = 50
    instance_types         = [var.eks_node_instance_type]
    vpc_security_group_ids = [aws_security_group.primary_eks_nodes.id]
  }

  eks_managed_node_groups = {
    primary_workers = {
      min_size       = var.primary_eks_node_group_min
      max_size       = var.primary_eks_node_group_max
      desired_size   = var.primary_eks_node_group_desired
      instance_types = [var.eks_node_instance_type]
      
      labels = {
        Environment = var.environment
        Region      = "primary"
      }

      tags = merge(local.tags, {
        "k8s.io/cluster-autoscaler/enabled"                      = "true"
        "k8s.io/cluster-autoscaler/${var.application_name}-primary-eks" = "owned"
      })
    }
  }

  tags = local.tags
}

# Secondary Region EKS Cluster
module "eks_secondary" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"
  providers = {
    aws = aws.secondary
  }

  cluster_name                   = "${var.application_name}-secondary-eks"
  cluster_version                = var.eks_version
  cluster_endpoint_public_access = true
  
  vpc_id     = module.vpc_secondary.vpc_id
  subnet_ids = module.vpc_secondary.private_subnets

  # Add security groups
  cluster_security_group_additional_rules = {
    egress_all = {
      description = "Allow all outbound traffic"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Enable EKS managed add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Managed node groups (scaled down for warm standby)
  eks_managed_node_group_defaults = {
    ami_type               = "AL2_x86_64"
    disk_size              = 50
    instance_types         = [var.eks_node_instance_type]
    vpc_security_group_ids = [aws_security_group.secondary_eks_nodes.id]
  }

  eks_managed_node_groups = {
    secondary_workers = {
      min_size       = var.secondary_eks_node_group_min
      max_size       = var.secondary_eks_node_group_max
      desired_size   = var.secondary_eks_node_group_desired
      instance_types = [var.eks_node_instance_type]
      
      labels = {
        Environment = var.environment
        Region      = "secondary"
      }

      tags = merge(local.tags, {
        "k8s.io/cluster-autoscaler/enabled"                        = "true"
        "k8s.io/cluster-autoscaler/${var.application_name}-secondary-eks" = "owned"
      })
    }
  }

  tags = local.tags
}

# Security groups for EKS nodes
resource "aws_security_group" "primary_eks_nodes" {
  provider    = aws.primary
  name        = "${var.application_name}-primary-eks-nodes-sg"
  description = "Security group for primary EKS nodes"
  vpc_id      = module.vpc_primary.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-eks-nodes-sg"
  })
}

resource "aws_security_group" "secondary_eks_nodes" {
  provider    = aws.secondary
  name        = "${var.application_name}-secondary-eks-nodes-sg"
  description = "Security group for secondary EKS nodes"
  vpc_id      = module.vpc_secondary.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = merge(local.tags, {
    Name = "${var.application_name}-secondary-eks-nodes-sg"
  })
}

# Output EKS cluster endpoints for reference
output "eks_primary_endpoint" {
  value       = module.eks_primary.cluster_endpoint
  description = "Endpoint for EKS cluster in primary region"
}

output "eks_secondary_endpoint" {
  value       = module.eks_secondary.cluster_endpoint
  description = "Endpoint for EKS cluster in secondary region"
}

# Output EKS cluster authentication information
output "eks_primary_certificate_authority_data" {
  value       = module.eks_primary.cluster_certificate_authority_data
  description = "Certificate authority data for EKS cluster in primary region"
  sensitive   = true
}

output "eks_secondary_certificate_authority_data" {
  value       = module.eks_secondary.cluster_certificate_authority_data
  description = "Certificate authority data for EKS cluster in secondary region"
  sensitive   = true
}