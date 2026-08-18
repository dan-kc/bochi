resource "aws_security_group" "alb" {
  name        = "bochi-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.bochi.id

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
resource "aws_lb" "bochi" {
  name               = "bochi-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true
}

# HTTP Listener (Port 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.bochi.arn
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

resource "aws_acm_certificate" "bochi" {
  domain_name       = local.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "bochi" {
  certificate_arn         = aws_acm_certificate.bochi.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.acm_validation : record.name]
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.bochi.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.bochi.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }
}

output "alb_dns_name" {
  value       = aws_lb.bochi.dns_name
  description = "DNS name of the Application Load Balancer"
}

output "https_listener_arn" {
  value       = aws_lb_listener.https.arn
  description = "ARN of the HTTPS listener for attaching listener rules"
}
