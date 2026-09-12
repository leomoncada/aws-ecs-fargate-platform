# Runbook: Deploy

## Staging

1. Ensure CI passes on the branch you want to deploy (lint, tests, dependency checks).
2. Merge or push to `staging`. GitHub Actions will:
   - Run CI (lint, backend tests, frontend tests, dependency audit).
   - Build and push backend and frontend images to ECR with tag `staging`.
   - Deploy workflow updates ECS services (backend and frontend) with `--force-new-deployment`.
3. Verify: open the staging ALB URL, check `/health` and the dashboard.

## Production

1. Ensure staging has been tested and the image you want is tagged `staging` in ECR.
2. In GitHub, configure the **production** environment with **Required reviewers** (Settings → Environments → production) so each deploy requires approval.
3. Merge or push to `prod`. GitHub Actions will:
   - Run CI.
   - **Deploy workflow (production)** will wait for approval if required reviewers are set.
   - After approval: promote `staging` image to tag `prod` in ECR for both backend and frontend.
   - Update ECS prod services with `--force-new-deployment`.
4. Verify: open the production ALB URL, check `/health` and the dashboard.

## Required GitHub secrets

- `AWS_BUILD_ROLE_ARN`, IAM role for the build job. Can push to ECR only.
- `AWS_DEPLOY_ROLE_ARN`, IAM role for the deploy and promotion jobs. Can update ECS.

  Both are created by `infra/global` (see `oidc.tf`) and are restricted by an
  OIDC `sub` condition: the build role only from `refs/heads/staging`, the
  deploy role only from the `staging` and `production` GitHub Environments.
- `ECR_REPOSITORY_BACKEND` — ECR repository name (e.g. `portfolio-backend`).
- `ECR_REPOSITORY_FRONTEND` — ECR repository name (e.g. `portfolio-frontend`).
- `ECS_CLUSTER_STAGING`, `ECS_SERVICE_BACKEND_STAGING`, `ECS_SERVICE_FRONTEND_STAGING`.
- `ECS_CLUSTER_PROD`, `ECS_SERVICE_BACKEND_PROD`, `ECS_SERVICE_FRONTEND_PROD`.

See [Rollback](rollback.md) if a deploy causes issues.
