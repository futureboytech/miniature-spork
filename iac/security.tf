# security.tf - Security groups for application components

# Primary Region Security Groups
resource "aws_security_group" "primary_alb" {
  provider    = aws.primary
  name        = "${var.application_name}-primary-alb-sg"
  description = "Security group for primary region Application Load Balancer"
  vpc_id      = module.vpc_primary.vpc_id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from the internet"
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from the internet"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-alb-sg"
  })
}

resource "aws_security_group" "primary_frontend" {
  provider    = aws.primary
  name        = "${var.application_name}-primary-frontend-sg"
  description = "Security group for primary region frontend servers"
  vpc_id      = module.vpc_primary.vpc_id
  
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.primary_alb.id]
    description     = "Allow HTTP traffic from the ALB"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-frontend-sg"
  })
}

resource "aws_security_group" "primary_app" {
  provider    = aws.primary
  name        = "${var.application_name}-primary-app-sg"
  description = "Security group for primary region application servers"
  vpc_id      = module.vpc_primary.vpc_id
  
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.primary_frontend.id]
    description     = "Allow traffic from frontend servers"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-app-sg"
  })
}

resource "aws_security_group" "primary_db" {
  provider    = aws.primary
  name        = "${var.application_name}-primary-db-sg"
  description = "Security group for primary region Aurora database"
  vpc_id      = module.vpc_primary.vpc_id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.primary_app.id]
    description     = "Allow PostgreSQL/Aurora traffic from application servers"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-primary-db-sg"
  })
}

# Secondary Region Security Groups
resource "aws_security_group" "secondary_alb" {
  provider    = aws.secondary
  name        = "${var.application_name}-secondary-alb-sg"
  description = "Security group for secondary region Application Load Balancer"
  vpc_id      = module.vpc_secondary.vpc_id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP traffic from the internet"
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS traffic from the internet"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-secondary-alb-sg"
  })
}

resource "aws_security_group" "secondary_frontend" {
  provider    = aws.secondary
  name        = "${var.application_name}-secondary-frontend-sg"
  description = "Security group for secondary region frontend servers"
  vpc_id      = module.vpc_secondary.vpc_id
  
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.secondary_alb.id]
    description     = "Allow HTTP traffic from the ALB"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-secondary-frontend-sg"
  })
}

resource "aws_security_group" "secondary_app" {
  provider    = aws.secondary
  name        = "${var.application_name}-secondary-app-sg"
  description = "Security group for secondary region application servers"
  vpc_id      = module.vpc_secondary.vpc_id
  
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.secondary_frontend.id]
    description     = "Allow traffic from frontend servers"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-secondary-app-sg"
  })
}

resource "aws_security_group" "secondary_db" {
  provider    = aws.secondary
  name        = "${var.application_name}-secondary-db-sg"
  description = "Security group for secondary region Aurora database"
  vpc_id      = module.vpc_secondary.vpc_id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.secondary_app.id]
    description     = "Allow PostgreSQL/Aurora traffic from application servers"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.tags, {
    Name = "${var.application_name}-secondary-db-sg"
  })
}
