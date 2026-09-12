# SNS topic for CloudWatch alarms
resource "aws_sns_topic" "alarms" {
  name = "portfolio-${var.env}-alarms"
  tags = {
    Name = "portfolio-${var.env}-alarms"
  }
}

# Allow CloudWatch to publish to this topic
resource "aws_sns_topic_policy" "alarms" {
  arn = aws_sns_topic.alarms.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchAlarms"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.alarms.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:alarm:*"
          }
        }
      }
    ]
  })
}

# Email subscription (only when alarm_email is set)
resource "aws_sns_topic_subscription" "alarms_email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- ECS Backend alarms ---

resource "aws_cloudwatch_metric_alarm" "backend_cpu" {
  alarm_name          = "portfolio-${var.env}-backend-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold_percent
  alarm_description   = "ECS backend CPU utilization above ${var.alarm_cpu_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.backend_service_name
  }
  tags = {
    Name = "portfolio-${var.env}-backend-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "backend_memory" {
  alarm_name          = "portfolio-${var.env}-backend-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_memory_threshold_percent
  alarm_description   = "ECS backend memory utilization above ${var.alarm_memory_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.backend_service_name
  }
  tags = {
    Name = "portfolio-${var.env}-backend-memory-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "backend_no_tasks" {
  alarm_name          = "portfolio-${var.env}-backend-no-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "ECS backend has no running tasks"
  # When the service or target group disappears the metric stops being
  # published. Without this the alarm goes to INSUFFICIENT_DATA, not ALARM.
  treat_missing_data = "breaching"
  alarm_actions      = [aws_sns_topic.alarms.arn]
  ok_actions         = [aws_sns_topic.alarms.arn]
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.backend_service_name
  }
  tags = {
    Name = "portfolio-${var.env}-backend-no-tasks"
  }
}

# --- ECS Frontend alarms ---

resource "aws_cloudwatch_metric_alarm" "frontend_cpu" {
  alarm_name          = "portfolio-${var.env}-frontend-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold_percent
  alarm_description   = "ECS frontend CPU utilization above ${var.alarm_cpu_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.frontend_service_name
  }
  tags = {
    Name = "portfolio-${var.env}-frontend-cpu-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "frontend_memory" {
  alarm_name          = "portfolio-${var.env}-frontend-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = var.alarm_period_seconds
  statistic           = "Average"
  threshold           = var.alarm_memory_threshold_percent
  alarm_description   = "ECS frontend memory utilization above ${var.alarm_memory_threshold_percent}%"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.frontend_service_name
  }
  tags = {
    Name = "portfolio-${var.env}-frontend-memory-high"
  }
}

resource "aws_cloudwatch_metric_alarm" "frontend_no_tasks" {
  alarm_name          = "portfolio-${var.env}-frontend-no-tasks"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RunningTaskCount"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "ECS frontend has no running tasks"
  # When the service or target group disappears the metric stops being
  # published. Without this the alarm goes to INSUFFICIENT_DATA, not ALARM.
  treat_missing_data = "breaching"
  alarm_actions      = [aws_sns_topic.alarms.arn]
  ok_actions         = [aws_sns_topic.alarms.arn]
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.frontend_service_name
  }
  tags = {
    Name = "portfolio-${var.env}-frontend-no-tasks"
  }
}

# --- ALB alarms (when alb_load_balancer_dimension is set) ---

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  count               = var.alb_load_balancer_dimension != "" ? 1 : 0
  alarm_name          = "portfolio-${var.env}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_alb_5xx_threshold
  alarm_description   = "ALB 5xx responses above ${var.alarm_alb_5xx_threshold}"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  dimensions = {
    LoadBalancer = var.alb_load_balancer_dimension
  }
  tags = {
    Name = "portfolio-${var.env}-alb-5xx"
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count               = var.alb_load_balancer_dimension != "" ? 1 : 0
  alarm_name          = "portfolio-${var.env}-alb-target-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = var.alarm_alb_5xx_threshold
  alarm_description   = "Application returned 5xx responses above ${var.alarm_alb_5xx_threshold}"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]
  dimensions = {
    LoadBalancer = var.alb_load_balancer_dimension
  }
  tags = {
    Name = "portfolio-${var.env}-alb-target-5xx"
  }
}

resource "aws_cloudwatch_metric_alarm" "backend_unhealthy_hosts" {
  count               = var.alb_load_balancer_dimension != "" && var.backend_target_group_arn_suffix != "" ? 1 : 0
  alarm_name          = "portfolio-${var.env}-alb-backend-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_alb_unhealthy_hosts_threshold
  alarm_description   = "Backend target group has unhealthy hosts"
  # When the service or target group disappears the metric stops being
  # published. Without this the alarm goes to INSUFFICIENT_DATA, not ALARM.
  treat_missing_data = "breaching"
  alarm_actions      = [aws_sns_topic.alarms.arn]
  ok_actions         = [aws_sns_topic.alarms.arn]
  dimensions = {
    LoadBalancer = var.alb_load_balancer_dimension
    TargetGroup  = var.backend_target_group_arn_suffix
  }
  tags = {
    Name = "portfolio-${var.env}-alb-backend-unhealthy-hosts"
  }
}

resource "aws_cloudwatch_metric_alarm" "frontend_unhealthy_hosts" {
  count               = var.alb_load_balancer_dimension != "" && var.frontend_target_group_arn_suffix != "" ? 1 : 0
  alarm_name          = "portfolio-${var.env}-alb-frontend-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_alb_unhealthy_hosts_threshold
  alarm_description   = "Frontend target group has unhealthy hosts"
  # When the service or target group disappears the metric stops being
  # published. Without this the alarm goes to INSUFFICIENT_DATA, not ALARM.
  treat_missing_data = "breaching"
  alarm_actions      = [aws_sns_topic.alarms.arn]
  ok_actions         = [aws_sns_topic.alarms.arn]
  dimensions = {
    LoadBalancer = var.alb_load_balancer_dimension
    TargetGroup  = var.frontend_target_group_arn_suffix
  }
  tags = {
    Name = "portfolio-${var.env}-alb-frontend-unhealthy-hosts"
  }
}
