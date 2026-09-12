# Observability

## Logging

### Structured logging configuration

- **Backend:** Application-level structured logging is configured in code (`app/logging_config.py`). Uses [structlog](https://www.structlog.org/) to emit **JSON logs to stdout** (one line per event with `timestamp`, `level`, `event`, and custom keys such as `method`, `path`, `status_code`). Set `LOG_JSON=false` for human-readable console output in local dev. ECS captures stdout via the `awslogs` driver and sends it to CloudWatch.
- **Frontend:** Next.js writes to stdout/stderr; ECS captures it with `awslogs` and sends it to CloudWatch. For structured (JSON) logs in the frontend, add a logger such as [pino](https://github.com/pinojs/pino) or winston with a JSON transport in a future iteration; current setup satisfies aggregation and search in CloudWatch Logs.

### Transport and retention

- **Backend / Frontend:** Log streams are sent to CloudWatch Logs via the `awslogs` driver in ECS task definitions (see `infra/modules/ecs/main.tf`). Log groups: `/ecs/portfolio-<env>-backend`, `/ecs/portfolio-<env>-frontend`. Retention: 14 days (configurable in Terraform).
- **Aggregation:** CloudWatch Logs Insights can query across log groups. Optionally export to S3 or a third-party (e.g. Datadog) via subscription filters.

## Metrics to collect

- **ECS:** CPUUtilization, MemoryUtilization per service (default in Container Insights).
- **ALB:** RequestCount, TargetResponseTime, HTTPCode_Target_5XX_Count, UnHealthyHostCount.
- **Application:** Backend can expose Prometheus-style metrics later; for now rely on ECS/ALB.

## Alerting

All alarms below are defined in Terraform (`infra/modules/cloudwatch-alarms`)
and covered by `infra/modules/cloudwatch-alarms/tests/alarms.tftest.hcl`.
They are created by a normal apply; nothing here has to be clicked together
in the console.

| Alarm | Metric | Fires when |
|---|---|---|
| `portfolio-<env>-<svc>-cpu-high` | `CPUUtilization` (AWS/ECS) | Above 85% for 2 periods |
| `portfolio-<env>-<svc>-memory-high` | `MemoryUtilization` (AWS/ECS) | Above 90% for 2 periods |
| `portfolio-<env>-<svc>-no-tasks` | `RunningTaskCount` (AWS/ECS) | Service has no running tasks |
| `portfolio-<env>-alb-5xx` | `HTTPCode_ELB_5XX_Count` | The load balancer itself returns 5xx |
| `portfolio-<env>-alb-target-5xx` | `HTTPCode_Target_5XX_Count` | The application returns 5xx |
| `portfolio-<env>-alb-<svc>-unhealthy-hosts` | `UnHealthyHostCount` | A target group has unhealthy targets |

Two details that are easy to get wrong and are worth calling out:

- **Both 5xx alarms exist on purpose.** `HTTPCode_ELB_5XX_Count` only counts
  errors the load balancer generates itself, such as having no healthy target.
  A 500 returned by FastAPI or Next.js is a *target* 5xx and is invisible to
  it. The incident runbook is written around application errors, so alarming
  only on the ELB metric would have left that runbook unreachable.
- **The no-tasks and unhealthy-hosts alarms set `treat_missing_data = "breaching"`.**
  When a service drops to zero tasks it stops publishing `RunningTaskCount`
  altogether. With the CloudWatch default the alarm would move to
  INSUFFICIENT_DATA rather than ALARM, so the outage that matters most would
  never page anyone.

Alarms publish to an SNS topic whose policy is scoped with both
`aws:SourceAccount` and `aws:SourceArn`. Set `alarm_email` to subscribe an
address; leave it empty and the topic is created with no subscription.

## Autoscaling

Both services scale on CPU *and* memory target tracking (`infra/modules/ecs`),
between `autoscaling_min_capacity` and `autoscaling_max_capacity`. Cooldowns
are deliberately asymmetric, 60s scaling out and 300s scaling in, so traffic
spikes are absorbed quickly but capacity is given up slowly.

`desired_count` is under a `lifecycle { ignore_changes }` block because
autoscaling owns it at runtime. Without that, any later apply would reset a
scaled-out service back to the minimum.

## Dashboards

Not implemented. Container Insights is enabled on the cluster, so ECS CPU and
memory are available in the console without further setup. A CloudWatch
dashboard resource is a reasonable next addition; it is deliberately not
described here as though it existed.
