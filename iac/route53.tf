# route53.tf - Route53 configurations for DNS failover

# Route53 Variables
variable "application_subdomain" {
  description = "Subdomain for the application"
  type        = string
  default     = "app"
}

# Get existing Route53 zone if it exists
data "aws_route53_zone" "domain" {
  provider = aws.primary
  name     = var.domain_name
  private_zone = false
}

# Create health check for primary region
resource "aws_route53_health_check" "primary" {
  provider          = aws.primary
  fqdn              = aws_lb.primary.dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-health-check"
  })
}

# Create DNS records for failover routing
resource "aws_route53_record" "primary" {
  provider = aws.primary
  zone_id  = data.aws_route53_zone.domain.zone_id
  name     = "${var.application_subdomain}.${var.domain_name}"
  type     = "A"
  
  failover_routing_policy {
    type = "PRIMARY"
  }
  
  health_check_id = aws_route53_health_check.primary.id
  
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  provider = aws.primary
  zone_id  = data.aws_route53_zone.domain.zone_id
  name     = "${var.application_subdomain}.${var.domain_name}"
  type     = "A"
  
  failover_routing_policy {
    type = "SECONDARY"
  }
  
  alias {
    name                   = aws_lb.secondary.dns_name
    zone_id                = aws_lb.secondary.zone_id
    evaluate_target_health = true
  }
}

# Create application load balancers in each region to expose the EKS clusters
resource "aws_lb" "primary" {
  provider           = aws.primary
  name               = "${var.application_name}-primary-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.primary_alb.id]
  subnets            = module.vpc_primary.public_subnets
  
  enable_deletion_protection = false
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-alb"
  })
}

resource "aws_lb" "secondary" {
  provider           = aws.secondary
  name               = "${var.application_name}-secondary-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.secondary_alb.id]
  subnets            = module.vpc_secondary.public_subnets
  
  enable_deletion_protection = false
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-secondary-alb"
  })
}

# Default listener for HTTP to HTTPS redirect
resource "aws_lb_listener" "primary_http" {
  provider          = aws.primary
  load_balancer_arn = aws_lb.primary.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "secondary_http" {
  provider          = aws.secondary
  load_balancer_arn = aws_lb.secondary.arn
  port              = "80"
  protocol          = "HTTP"
  
  default_action {
    type = "redirect"
    
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Create default HTTPS listeners
# Note: In a real implementation, you would need to add ACM certificates
resource "aws_lb_listener" "primary_https" {
  provider          = aws.primary
  load_balancer_arn = aws_lb.primary.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  # certificate_arn   = aws_acm_certificate.primary.arn
  
  default_action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "Health check endpoint"
      status_code  = "200"
    }
  }
}

resource "aws_lb_listener" "secondary_https" {
  provider          = aws.secondary
  load_balancer_arn = aws_lb.secondary.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  # certificate_arn   = aws_acm_certificate.secondary.arn
  
  default_action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "Health check endpoint"
      status_code  = "200"
    }
  }
}

# Create a health check path for Route53
resource "aws_lb_listener_rule" "primary_health" {
  provider     = aws.primary
  listener_arn = aws_lb_listener.primary_https.arn
  priority     = 1
  
  action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "Healthy"
      status_code  = "200"
    }
  }
  
  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

resource "aws_lb_listener_rule" "secondary_health" {
  provider     = aws.secondary
  listener_arn = aws_lb_listener.secondary_https.arn
  priority     = 1
  
  action {
    type = "fixed-response"
    
    fixed_response {
      content_type = "text/plain"
      message_body = "Healthy"
      status_code  = "200"
    }
  }
  
  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

# Output DNS information
output "application_url" {
  value       = "https://${var.application_subdomain}.${var.domain_name}"
  description = "URL for the application with failover routing"
}

# Note: For production use, you would need to create and validate ACM certificates
# and configure proper target groups for the EKS clusters