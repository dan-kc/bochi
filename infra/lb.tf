# Security group for Application Load Balancer
resource "aws_security_group" "alb" {
  name        = "tofustash-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.tofustash.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP from anywhere"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS from anywhere"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
}

# Application Load Balancer
resource "aws_lb" "tofustash" {
  name               = "tofustash-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_b.id]

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true
}

# ACM Certificate for TLS
resource "aws_acm_certificate" "tofustash" {
  domain_name               = "tofustash.com"
  subject_alternative_names = ["*.tofustash.com"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# HTTPS Listener (Port 443)
# Before this is define, you must already have ACM cert setup
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.tofustash.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.tofustash.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

# HTTP Listener (Port 80) - Redirect to HTTPS
resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.tofustash.arn
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

# Outputs
# output "alb_dns_name" {
#   value       = aws_lb.tofustash.dns_name
#   description = "DNS name of the Application Load Balancer"
# }
#
# output "certificate_arn" {
#   value       = aws_acm_certificate.tofustash.arn
#   description = "ARN of the ACM certificate"
# }
#
# output "certificate_domain_validation_options" {
#   value       = aws_acm_certificate.tofustash.domain_validation_options
#   description = "Domain validation options for the certificate - add these DNS records to Cloudflare"
# }
#
# output "https_listener_arn" {
#   value       = aws_lb_listener.https.arn
#   description = "ARN of the HTTPS listener for attaching listener rules"
# }
