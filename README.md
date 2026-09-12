# Portfolio Dashboard

Full-stack application (FastAPI backend + Next.js frontend) deployed on AWS with Terraform: VPC, ECS Fargate, ALB, and shared ECR. CI/CD via GitHub Actions: build on staging, then promote the same image digest to prod behind an approval gate.

---

## Repository structure

| Path | Description |
|------|-------------|
| **`backend/`** | FastAPI API: health, assets, portfolio insights. See [backend/README.md](backend/README.md). |
| **`frontend/`** | Next.js 14 dashboard (Tailwind). See [frontend/README.md](frontend/README.md). |
| **`infra/`** | Terraform: modules and root for LocalStack. **Per-env applies:** use `infra/environments/staging/` and `infra/environments/prod/` (each has its own state and tfvars). See [infra/README.md](infra/README.md). |
| **`infra/global/`** | Terraform: shared ECR repos (one per app). Apply once per account. See [infra/global/README.md](infra/global/README.md). |
| **`.github/workflows/`** | `ci.yml`: lint, test, Terraform tests, build, then deploy staging as a dependent job so a deploy can never race its own image. `deploy.yml`: production promotion, pinned to an image digest. |
| **`scripts/`** | Local validation (e.g. `validate-localstack.sh` for Terraform against LocalStack). |
| **`OBSERVABILITY.md`** | Logging, metrics, alerting, dashboards. |
| **`DECISIONS.md`** | Architecture and technology choices. |
| **`docs/runbooks/`** | Runbooks: [Deploy](docs/runbooks/deploy.md), [Rollback](docs/runbooks/rollback.md), [Incidents](docs/runbooks/incidents.md). |

---

## Testing

Terraform modules are covered by native `terraform test` suites using
`mock_provider`, so the whole infrastructure suite runs in CI with no AWS
credentials and no cost:

```bash
for d in vpc alb ecs cloudwatch-alarms; do
  terraform -chdir="infra/modules/$d" init -backend=false
  terraform -chdir="infra/modules/$d" test
done
```

50 assertions across VPC, ALB, ECS and the CloudWatch alarms.

## How to use

### Local development

**Option A — Docker Compose (backend + frontend):**

```bash
cp .env.example .env   # optional: adjust NEXT_PUBLIC_API_URL
docker compose up --build
```

- Frontend: http://localhost:3000  
- Backend: http://localhost:8000 (docs: http://localhost:8000/docs)

**Option B — Run backend and frontend separately:**

```bash
# Backend
cd backend && pip install -r requirements.txt && uvicorn app.main:app --reload --port 8000

# Frontend (another terminal)
cd frontend && npm install && npm run dev
```

Set `NEXT_PUBLIC_API_URL=http://localhost:8000` for the frontend (e.g. in `.env` or in the shell).

### Infrastructure (AWS)

1. **Global (once):** Create shared ECR repositories.
   ```bash
   cd infra/global
   terraform init && terraform plan && terraform apply
   ```
2. **Per environment:** Each environment has its own folder and state. Apply from `infra/environments/staging/` or `infra/environments/prod/`.
   ```bash
   cd infra/environments/staging   # or prod
   cp terraform.tfvars.example terraform.tfvars
   # Edit main.tf: set S3 bucket for backend. Edit terraform.tfvars: backend_image, frontend_image (tag :staging or :prod).
   terraform init && terraform plan && terraform apply
   ```
3. Use `terraform output alb_dns_name` for the dashboard URL.

Details, apply order, and CI/CD secrets: [infra/README.md](infra/README.md).

### CI/CD

- **Push to `staging`:** CI runs lint, backend and frontend tests, dependency audits, builds images, pushes to ECR with tag `staging`; Deploy workflow updates ECS staging.
- **Push to `prod`:** CI runs the same checks; Deploy workflow promotes the `staging` image to tag `prod` and updates ECS prod. **Production** deploy uses the GitHub Environment `production`; configure **Required reviewers** in Settings → Environments → production so each prod deploy requires approval.

Secrets: `AWS_BUILD_ROLE_ARN` and `AWS_DEPLOY_ROLE_ARN` (two roles: the build job can push images and nothing else, only the deploy job can touch ECS), `ECR_REPOSITORY_BACKEND`, `ECR_REPOSITORY_FRONTEND` (repo names), and ECS cluster/service names for staging and prod. See [docs/runbooks/deploy.md](docs/runbooks/deploy.md).

### Local validation (no AWS)

- Terraform + Actionlint: see [infra/README.md](infra/README.md#validate-with-localstack-without-aws).
- Optional: `./scripts/validate-localstack.sh plan` to run Terraform plan against LocalStack (ECR/ALB/ECS require LocalStack Pro for apply).

---

## Requirements

- **Local:** Docker (for Compose), or Node 20 + Python 3.12 for running apps directly.
- **Infra:** Terraform >= 1.5, AWS credentials.
- **CI/CD:** GitHub repo with OIDC configured for AWS and the required secrets.
