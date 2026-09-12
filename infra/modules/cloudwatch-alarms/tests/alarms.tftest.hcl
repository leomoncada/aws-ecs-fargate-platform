mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }
  override_data {
    target = data.aws_region.current
    values = {
      name = "us-east-1"
    }
  }
}

variables {
  env                   = "test"
  alarm_email           = ""
  cluster_name          = "portfolio-test-cluster"
  backend_service_name  = "portfolio-test-backend"
  frontend_service_name = "portfolio-test-frontend"
}

run "sns_topic_named_with_environment" {
  command = plan

  assert {
    condition     = aws_sns_topic.alarms.name == "portfolio-test-alarms"
    error_message = "SNS topic should be named with environment"
  }
}

run "no_email_subscription_by_default" {
  command = plan

  assert {
    condition     = length(aws_sns_topic_subscription.alarms_email) == 0
    error_message = "No email subscription when alarm_email is empty"
  }
}

run "email_subscription_when_set" {
  command = plan

  variables {
    alarm_email = "alerts@example.com"
  }

  assert {
    condition     = length(aws_sns_topic_subscription.alarms_email) == 1
    error_message = "Email subscription should exist when alarm_email is set"
  }
}

run "backend_cpu_alarm_config" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_cpu.alarm_name == "portfolio-test-backend-cpu-high"
    error_message = "Backend CPU alarm should be named with environment"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_cpu.metric_name == "CPUUtilization"
    error_message = "Backend CPU alarm should use CPUUtilization metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_cpu.namespace == "AWS/ECS"
    error_message = "Backend CPU alarm should use AWS/ECS namespace"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_cpu.threshold == 85
    error_message = "Backend CPU alarm threshold should default to 85"
  }
}

run "backend_memory_alarm_config" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_memory.metric_name == "MemoryUtilization"
    error_message = "Backend memory alarm should use MemoryUtilization metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_memory.threshold == 90
    error_message = "Backend memory alarm threshold should default to 90"
  }
}

run "backend_no_tasks_alarm" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_no_tasks.metric_name == "RunningTaskCount"
    error_message = "No-tasks alarm should use RunningTaskCount metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_no_tasks.comparison_operator == "LessThanThreshold"
    error_message = "No-tasks alarm should trigger when below threshold"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_no_tasks.threshold == 1
    error_message = "No-tasks alarm threshold should be 1"
  }
}

run "frontend_alarms_exist" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.frontend_cpu.alarm_name == "portfolio-test-frontend-cpu-high"
    error_message = "Frontend CPU alarm should exist"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.frontend_memory.alarm_name == "portfolio-test-frontend-memory-high"
    error_message = "Frontend memory alarm should exist"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.frontend_no_tasks.alarm_name == "portfolio-test-frontend-no-tasks"
    error_message = "Frontend no-tasks alarm should exist"
  }
}

run "no_alb_alarms_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.alb_5xx) == 0
    error_message = "ALB 5xx alarm should not exist when dimension is empty"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.backend_unhealthy_hosts) == 0
    error_message = "Backend unhealthy hosts alarm should not exist when dimension is empty"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.frontend_unhealthy_hosts) == 0
    error_message = "Frontend unhealthy hosts alarm should not exist when dimension is empty"
  }
}

run "alb_alarms_when_dimension_set" {
  command = plan

  variables {
    alb_load_balancer_dimension      = "app/portfolio-test-alb/abc123"
    backend_target_group_arn_suffix  = "targetgroup/portfolio-test-backend/def456"
    frontend_target_group_arn_suffix = "targetgroup/portfolio-test-frontend/ghi789"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.alb_5xx) == 1
    error_message = "ALB 5xx alarm should exist when dimension is set"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_5xx[0].metric_name == "HTTPCode_ELB_5XX_Count"
    error_message = "ALB 5xx alarm should use correct metric"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_5xx[0].namespace == "AWS/ApplicationELB"
    error_message = "ALB 5xx alarm should use ApplicationELB namespace"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.backend_unhealthy_hosts) == 1
    error_message = "Backend unhealthy hosts alarm should exist"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.frontend_unhealthy_hosts) == 1
    error_message = "Frontend unhealthy hosts alarm should exist"
  }
}

run "custom_thresholds" {
  command = plan

  variables {
    alarm_cpu_threshold_percent    = 75
    alarm_memory_threshold_percent = 85
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_cpu.threshold == 75
    error_message = "CPU threshold should follow variable"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_memory.threshold == 85
    error_message = "Memory threshold should follow variable"
  }
}

# An ECS service that drops to zero tasks stops publishing RunningTaskCount
# altogether. With the CloudWatch default of treat_missing_data = "missing"
# the alarm goes to INSUFFICIENT_DATA instead of ALARM, so the outage that
# matters most never pages anyone.
run "no_tasks_alarms_treat_missing_data_as_breaching" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_no_tasks.treat_missing_data == "breaching"
    error_message = "Backend no-tasks alarm must treat missing data as breaching, or it cannot fire when the service has zero tasks"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.frontend_no_tasks.treat_missing_data == "breaching"
    error_message = "Frontend no-tasks alarm must treat missing data as breaching, or it cannot fire when the service has zero tasks"
  }
}

# Same failure mode: an empty target group stops publishing UnHealthyHostCount.
# These alarms are conditional on the ALB dimensions being supplied.
run "unhealthy_hosts_alarms_treat_missing_data_as_breaching" {
  command = plan

  variables {
    alb_load_balancer_dimension      = "app/portfolio-test-alb/abc123"
    backend_target_group_arn_suffix  = "targetgroup/portfolio-test-backend/def456"
    frontend_target_group_arn_suffix = "targetgroup/portfolio-test-frontend/ghi789"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backend_unhealthy_hosts[0].treat_missing_data == "breaching"
    error_message = "Backend unhealthy-hosts alarm must treat missing data as breaching"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.frontend_unhealthy_hosts[0].treat_missing_data == "breaching"
    error_message = "Frontend unhealthy-hosts alarm must treat missing data as breaching"
  }
}

# HTTPCode_ELB_5XX_Count only counts errors the load balancer itself generates.
# A 500 returned by FastAPI or Next.js is a Target 5xx and is invisible to it,
# which is precisely the case docs/runbooks/incidents.md is written around.
run "alarm_on_application_5xx_not_only_load_balancer_5xx" {
  command = plan

  variables {
    alb_load_balancer_dimension = "app/portfolio-test-alb/abc123"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_target_5xx[0].metric_name == "HTTPCode_Target_5XX_Count"
    error_message = "There must be an alarm on HTTPCode_Target_5XX_Count so application errors page someone"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_target_5xx[0].namespace == "AWS/ApplicationELB"
    error_message = "Target 5xx alarm should use the AWS/ApplicationELB namespace"
  }
}
