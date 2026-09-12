mock_provider "aws" {}

variables {
  vpc_id            = "vpc-test123"
  public_subnet_ids = ["subnet-aaa", "subnet-bbb"]
  env               = "test"
  certificate_arn   = ""
}

run "alb_is_external" {
  command = plan

  assert {
    condition     = aws_lb.main.internal == false
    error_message = "ALB should be internet-facing"
  }

  assert {
    condition     = aws_lb.main.load_balancer_type == "application"
    error_message = "Should be an application load balancer"
  }
}

run "alb_tagged_with_environment" {
  command = plan

  assert {
    condition     = aws_lb.main.tags["Name"] == "portfolio-test-alb"
    error_message = "ALB Name tag should include environment"
  }
}

run "backend_target_group_on_port_8000" {
  command = plan

  assert {
    condition     = aws_lb_target_group.backend.port == 8000
    error_message = "Backend TG should listen on port 8000"
  }

  assert {
    condition     = aws_lb_target_group.backend.target_type == "ip"
    error_message = "Backend TG should use IP target type (Fargate)"
  }
}

run "backend_health_check_path" {
  command = plan

  assert {
    condition     = aws_lb_target_group.backend.health_check[0].path == "/health"
    error_message = "Backend health check should use /health"
  }
}

run "frontend_target_group_on_port_3000" {
  command = plan

  assert {
    condition     = aws_lb_target_group.frontend.port == 3000
    error_message = "Frontend TG should listen on port 3000"
  }
}

run "frontend_health_check_path" {
  command = plan

  assert {
    condition     = aws_lb_target_group.frontend.health_check[0].path == "/api/health"
    error_message = "Frontend health check should use /api/health"
  }
}

run "http_forward_when_no_certificate" {
  command = plan

  assert {
    condition     = length(aws_lb_listener.http_forward) == 1
    error_message = "HTTP forward listener should exist when no certificate"
  }

  assert {
    condition     = length(aws_lb_listener.http_redirect) == 0
    error_message = "HTTP redirect listener should not exist when no certificate"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0
    error_message = "HTTPS listener should not exist when no certificate"
  }
}

run "http_redirect_when_certificate_set" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/test"
  }

  assert {
    condition     = length(aws_lb_listener.http_redirect) == 1
    error_message = "HTTP redirect listener should exist when certificate is set"
  }

  assert {
    condition     = length(aws_lb_listener.http_forward) == 0
    error_message = "HTTP forward listener should not exist when certificate is set"
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1
    error_message = "HTTPS listener should exist when certificate is set"
  }
}

run "security_group_allows_http_and_https" {
  command = plan

  assert {
    condition     = aws_security_group.alb.name == "portfolio-test-alb-sg"
    error_message = "ALB SG should be named with environment"
  }
}
