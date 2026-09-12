resource "aws_ecs_cluster" "main" {
  name = "portfolio-${var.env}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = {
    Name = "portfolio-${var.env}-cluster"
  }
}

# Execution role (pull images, logs)
resource "aws_iam_role" "execution" {
  name = "portfolio-${var.env}-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task role (for app; optional SSM/Secrets access via task_secrets_manager_arns / task_ssm_parameter_arns)
resource "aws_iam_role" "task" {
  name = "portfolio-${var.env}-ecs-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
      }
    ]
  })
}

resource "aws_iam_role_policy" "task_secrets" {
  count = length(var.task_secrets_manager_arns) + length(var.task_ssm_parameter_arns) > 0 ? 1 : 0

  name = "portfolio-${var.env}-ecs-task-secrets"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      length(var.task_secrets_manager_arns) > 0 ? [
        {
          Effect   = "Allow"
          Action   = "secretsmanager:GetSecretValue"
          Resource = var.task_secrets_manager_arns
        }
      ] : [],
      length(var.task_ssm_parameter_arns) > 0 ? [
        {
          Effect   = "Allow"
          Action   = "ssm:GetParameters"
          Resource = var.task_ssm_parameter_arns
        }
      ] : []
    )
  })
}

# ECS tasks security group: ALB → ECS; frontend → backend (same SG) for direct communication
resource "aws_security_group" "ecs" {
  name        = "portfolio-${var.env}-ecs-sg"
  description = "ECS: ALB and service-to-service (frontend→backend)"
  vpc_id      = var.vpc_id
  # ALB to backend and frontend
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }
  # Frontend → backend direct (Cloud Map private DNS); same SG
  ingress {
    from_port = 8000
    to_port   = 8000
    protocol  = "tcp"
    self      = true
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "portfolio-${var.env}-ecs-sg"
  }
}

# Backend task definition
resource "aws_ecs_task_definition" "backend" {
  family                   = "portfolio-${var.env}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory_mb
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([
    {
      name         = "backend"
      image        = var.backend_image
      essential    = true
      portMappings = [{ containerPort = 8000, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/portfolio-${var.env}-backend"
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        { name = "ENV", value = var.env },
        { name = "ALLOWED_ORIGINS", value = var.allowed_origins }
      ]
    }
  ])
  tags = {
    Name = "portfolio-${var.env}-backend"
  }
}

# Frontend task definition: direct communication to backend via private DNS (Cloud Map)
locals {
  backend_url = "http://backend.portfolio-${var.env}.local:8000"
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "portfolio-${var.env}-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory_mb
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([
    {
      name         = "frontend"
      image        = var.frontend_image
      essential    = true
      portMappings = [{ containerPort = 3000, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/portfolio-${var.env}-frontend"
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
      environment = [
        { name = "NODE_ENV", value = "production" },
        # Backend via private DNS (Cloud Map); direct frontend→backend traffic without ALB
        { name = "NEXT_PUBLIC_API_URL", value = local.backend_url }
      ]
    }
  ])
  tags = {
    Name = "portfolio-${var.env}-frontend"
  }
}

# CloudWatch log groups
resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/portfolio-${var.env}-backend"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/portfolio-${var.env}-frontend"
  retention_in_days = 14
}

data "aws_region" "current" {}

# Service discovery: private DNS so frontend can call backend without going through the ALB
resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "portfolio-${var.env}.local"
  description = "Private DNS for ECS service discovery"
  vpc         = var.vpc_id
  tags = {
    Name = "portfolio-${var.env}-sd-namespace"
  }
}

resource "aws_service_discovery_service" "backend" {
  name = "backend"
  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.main.id
    routing_policy = "MULTIVALUE"
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
  health_check_custom_config {
    failure_threshold = 1
  }
  tags = {
    Name = "portfolio-${var.env}-backend"
  }
}

# Backend service (registered in Cloud Map for frontend→backend private DNS)
resource "aws_ecs_service" "backend" {
  name            = "portfolio-${var.env}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.autoscaling_min_capacity
  launch_type     = "FARGATE"

  # A failed deployment should undo itself rather than sit there crash-looping.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Give a cold container time to answer before the ALB declares it unhealthy.
  health_check_grace_period_seconds = 60

  lifecycle {
    # Autoscaling owns desired_count at runtime. Without this, any later
    # apply resets a scaled-out service back to the minimum.
    ignore_changes = [desired_count]
  }
  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = var.alb_backend_tg_arn
    container_name   = "backend"
    container_port   = 8000
  }
  service_registries {
    registry_arn = aws_service_discovery_service.backend.arn
  }
  depends_on = [aws_cloudwatch_log_group.backend]
  tags = {
    Name = "portfolio-${var.env}-backend"
  }
}

# Frontend service
resource "aws_ecs_service" "frontend" {
  name            = "portfolio-${var.env}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.autoscaling_min_capacity
  launch_type     = "FARGATE"

  # A failed deployment should undo itself rather than sit there crash-looping.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Give a cold container time to answer before the ALB declares it unhealthy.
  health_check_grace_period_seconds = 60

  lifecycle {
    # Autoscaling owns desired_count at runtime. Without this, any later
    # apply resets a scaled-out service back to the minimum.
    ignore_changes = [desired_count]
  }
  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = var.alb_frontend_tg_arn
    container_name   = "frontend"
    container_port   = 3000
  }
  depends_on = [aws_cloudwatch_log_group.frontend]
  tags = {
    Name = "portfolio-${var.env}-frontend"
  }
}

# --- Autoscaling (Application Auto Scaling) ---

# Backend: scalable target
resource "aws_appautoscaling_target" "backend" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Backend: CPU scaling policy
resource "aws_appautoscaling_policy" "backend_cpu" {
  name               = "portfolio-${var.env}-backend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_target_cpu_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Backend: memory scaling policy
resource "aws_appautoscaling_policy" "backend_memory" {
  name               = "portfolio-${var.env}-backend-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend.resource_id
  scalable_dimension = aws_appautoscaling_target.backend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.autoscaling_target_memory_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Frontend: scalable target
resource "aws_appautoscaling_target" "frontend" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.frontend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Frontend: CPU scaling policy
resource "aws_appautoscaling_policy" "frontend_cpu" {
  name               = "portfolio-${var.env}-frontend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.frontend.resource_id
  scalable_dimension = aws_appautoscaling_target.frontend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.frontend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_target_cpu_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Frontend: memory scaling policy
resource "aws_appautoscaling_policy" "frontend_memory" {
  name               = "portfolio-${var.env}-frontend-memory"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.frontend.resource_id
  scalable_dimension = aws_appautoscaling_target.frontend.scalable_dimension
  service_namespace  = aws_appautoscaling_target.frontend.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = var.autoscaling_target_memory_percent
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
