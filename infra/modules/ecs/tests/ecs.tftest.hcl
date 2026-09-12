mock_provider "aws" {
  override_data {
    target = data.aws_region.current
    values = {
      name = "us-east-1"
    }
  }
}

variables {
  env                   = "test"
  vpc_id                = "vpc-test123"
  app_subnet_ids        = ["subnet-aaa", "subnet-bbb"]
  backend_image         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/portfolio-backend:test"
  frontend_image        = "123456789012.dkr.ecr.us-east-1.amazonaws.com/portfolio-frontend:test"
  alb_backend_tg_arn    = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/backend/abc"
  alb_frontend_tg_arn   = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/frontend/def"
  alb_security_group_id = "sg-test123"
  ecs_cpu               = 256
  ecs_memory_mb         = 512
}

run "cluster_named_with_environment" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.main.name == "portfolio-test-cluster"
    error_message = "Cluster name should include environment"
  }
}

run "container_insights_enabled" {
  command = plan

  assert {
    condition     = contains([for s in aws_ecs_cluster.main.setting : s.value if s.name == "containerInsights"], "enabled")
    error_message = "Container Insights should be enabled"
  }
}

run "backend_task_definition_config" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.backend.family == "portfolio-test-backend"
    error_message = "Backend task family should include environment"
  }

  assert {
    condition     = aws_ecs_task_definition.backend.network_mode == "awsvpc"
    error_message = "Backend should use awsvpc network mode"
  }

  assert {
    condition     = tolist(aws_ecs_task_definition.backend.requires_compatibilities)[0] == "FARGATE"
    error_message = "Backend should require Fargate"
  }

  assert {
    condition     = aws_ecs_task_definition.backend.cpu == "256"
    error_message = "Backend CPU should match variable"
  }

  assert {
    condition     = aws_ecs_task_definition.backend.memory == "512"
    error_message = "Backend memory should match variable"
  }
}

run "frontend_task_definition_config" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.frontend.family == "portfolio-test-frontend"
    error_message = "Frontend task family should include environment"
  }

  assert {
    condition     = aws_ecs_task_definition.frontend.network_mode == "awsvpc"
    error_message = "Frontend should use awsvpc network mode"
  }
}

run "backend_service_uses_fargate" {
  command = plan

  assert {
    condition     = aws_ecs_service.backend.launch_type == "FARGATE"
    error_message = "Backend service should use FARGATE launch type"
  }
}

run "frontend_service_uses_fargate" {
  command = plan

  assert {
    condition     = aws_ecs_service.frontend.launch_type == "FARGATE"
    error_message = "Frontend service should use FARGATE launch type"
  }
}

run "services_not_assigned_public_ip" {
  command = plan

  assert {
    condition     = aws_ecs_service.backend.network_configuration[0].assign_public_ip == false
    error_message = "Backend should not have public IP"
  }

  assert {
    condition     = aws_ecs_service.frontend.network_configuration[0].assign_public_ip == false
    error_message = "Frontend should not have public IP"
  }
}

run "log_groups_have_retention" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.backend.retention_in_days == 14
    error_message = "Backend log group should retain 14 days"
  }

  assert {
    condition     = aws_cloudwatch_log_group.frontend.retention_in_days == 14
    error_message = "Frontend log group should retain 14 days"
  }
}

run "autoscaling_default_capacity" {
  command = plan

  assert {
    condition     = aws_appautoscaling_target.backend.min_capacity == 1
    error_message = "Backend autoscaling min should default to 1"
  }

  assert {
    condition     = aws_appautoscaling_target.backend.max_capacity == 4
    error_message = "Backend autoscaling max should default to 4"
  }

  assert {
    condition     = aws_appautoscaling_target.frontend.min_capacity == 1
    error_message = "Frontend autoscaling min should default to 1"
  }

  assert {
    condition     = aws_appautoscaling_target.frontend.max_capacity == 4
    error_message = "Frontend autoscaling max should default to 4"
  }
}

run "autoscaling_custom_capacity" {
  command = plan

  variables {
    autoscaling_min_capacity = 2
    autoscaling_max_capacity = 8
  }

  assert {
    condition     = aws_appautoscaling_target.backend.min_capacity == 2
    error_message = "Backend autoscaling min should follow variable"
  }

  assert {
    condition     = aws_appautoscaling_target.backend.max_capacity == 8
    error_message = "Backend autoscaling max should follow variable"
  }
}

run "no_secrets_policy_by_default" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policy.task_secrets) == 0
    error_message = "No secrets policy should be created when no ARNs provided"
  }
}

run "secrets_policy_when_arns_provided" {
  command = plan

  variables {
    task_secrets_manager_arns = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:db-creds"]
  }

  assert {
    condition     = length(aws_iam_role_policy.task_secrets) == 1
    error_message = "Secrets policy should be created when ARNs provided"
  }
}

run "ecs_security_group_named" {
  command = plan

  assert {
    condition     = aws_security_group.ecs.name == "portfolio-test-ecs-sg"
    error_message = "ECS SG should be named with environment"
  }
}

run "service_discovery_namespace" {
  command = plan

  assert {
    condition     = aws_service_discovery_private_dns_namespace.main.name == "portfolio-test.local"
    error_message = "Service discovery namespace should use environment"
  }
}

# Without a circuit breaker a crash-looping deployment is reported as a
# successful deploy and stays broken until someone notices by hand.
run "services_roll_back_automatically_on_failed_deployment" {
  command = plan

  assert {
    condition     = aws_ecs_service.backend.deployment_circuit_breaker[0].enable
    error_message = "Backend service must enable the deployment circuit breaker"
  }

  assert {
    condition     = aws_ecs_service.backend.deployment_circuit_breaker[0].rollback
    error_message = "Backend circuit breaker must roll back, not just stop the deployment"
  }

  assert {
    condition     = aws_ecs_service.frontend.deployment_circuit_breaker[0].enable
    error_message = "Frontend service must enable the deployment circuit breaker"
  }

  assert {
    condition     = aws_ecs_service.frontend.deployment_circuit_breaker[0].rollback
    error_message = "Frontend circuit breaker must roll back, not just stop the deployment"
  }
}

# A container that is still warming up must not be killed by the load balancer
# health check before it has had a chance to answer.
run "services_allow_a_health_check_grace_period" {
  command = plan

  assert {
    condition     = aws_ecs_service.backend.health_check_grace_period_seconds > 0
    error_message = "Backend service needs a health check grace period for slow starts"
  }

  assert {
    condition     = aws_ecs_service.frontend.health_check_grace_period_seconds > 0
    error_message = "Frontend service needs a health check grace period for slow starts"
  }
}
