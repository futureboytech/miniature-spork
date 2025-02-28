# eks-alb-integration.tf - Integration between EKS clusters and ALBs

# Variables for the EKS application
variable "app_port" {
  description = "Port the application listens on in Kubernetes"
  type        = number
  default     = 8080
}

variable "app_health_check_path" {
  description = "Path for health check of the application"
  type        = string
  default     = "/healthz"
}

# Create target groups for the EKS applications
resource "aws_lb_target_group" "primary_app" {
  provider    = aws.primary
  name        = "${var.application_name}-primary-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = module.vpc_primary.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.app_health_check_path
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-299"
  }
  
  tags = local.tags
}

resource "aws_lb_target_group" "secondary_app" {
  provider    = aws.secondary
  name        = "${var.application_name}-secondary-tg"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = module.vpc_secondary.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = var.app_health_check_path
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-299"
  }
  
  tags = local.tags
}

# Add listener rules to forward traffic to the EKS applications
resource "aws_lb_listener_rule" "primary_app" {
  provider     = aws.primary
  listener_arn = aws_lb_listener.primary_https.arn
  priority     = 100
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.primary_app.arn
  }
  
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

resource "aws_lb_listener_rule" "secondary_app" {
  provider     = aws.secondary
  listener_arn = aws_lb_listener.secondary_https.arn
  priority     = 100
  
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.secondary_app.arn
  }
  
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# IRSA setup for AWS Load Balancer Controller
resource "aws_iam_policy" "aws_load_balancer_controller" {
  provider    = aws.primary
  name        = "${var.application_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for AWS Load Balancer Controller"
  
  # This is a simplified policy. In production, you would use the full AWS Load Balancer Controller policy
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeSubnets",
          "ec2:DescribeAvailabilityZones",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "aws_load_balancer_controller_secondary" {
  provider    = aws.secondary
  name        = "${var.application_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "Policy for AWS Load Balancer Controller in secondary region"
  
  # Same policy as primary region
  policy = aws_iam_policy.aws_load_balancer_controller.policy
}

# Outputs for EKS and ALB integration
output "primary_target_group_arn" {
  value       = aws_lb_target_group.primary_app.arn
  description = "ARN of the primary region target group"
}

output "secondary_target_group_arn" {
  value       = aws_lb_target_group.secondary_app.arn
  description = "ARN of the secondary region target group"
}

# Note: In a real implementation, you would:
# 1. Install AWS Load Balancer Controller in each EKS cluster
# 2. Define Kubernetes Ingress resources to route traffic to your applications
# 3. Set up proper IAM roles for service accounts (IRSA) for EKS pods
# 4. Use Kubernetes Services of type NodePort or ClusterIP with Ingress resources

# The following is a sample of how you might set up IRSA for the AWS Load Balancer Controller
/*
module "lb_controller_role_primary" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "${var.application_name}-primary-lb-controller"
  
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_primary.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

module "lb_controller_role_secondary" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "${var.application_name}-secondary-lb-controller"
  
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks_secondary.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
*/