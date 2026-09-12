# Runbook: Rollback ECS deployment

Use this when a new deployment causes errors (5xx, broken UI, or failed health checks) and you need to revert to the previous task definition or image.

## Option 1: Redeploy previous image tag (recommended)

If you previously promoted a known-good image to `prod` (or use `staging`), you can re-tag and force a new deployment.

1. **Identify the last known good image** in ECR (e.g. by digest or an older tag like `staging` or a specific SHA tag from CI).
2. **Re-tag that image as `prod`** (or the tag your ECS service uses):
   ```bash
   # Example: promote staging (or a specific digest) to prod again
   aws ecr batch-get-image --repository-name portfolio-backend --image-ids imageTag=staging \
     --query 'images[0].imageManifest' --output text > /tmp/manifest.json
   aws ecr put-image --repository-name portfolio-backend --image-tag prod --image-manifest file:///tmp/manifest.json
   # Repeat for portfolio-frontend if needed.
   ```
3. **Force a new ECS deployment** so the service pulls the re-tagged image:
   ```bash
   aws ecs update-service --cluster portfolio-prod-cluster --service portfolio-prod-backend --force-new-deployment --region us-east-1
   aws ecs update-service --cluster portfolio-prod-cluster --service portfolio-prod-frontend --force-new-deployment --region us-east-1
   ```
4. Wait for the deployment to reach `RUNNING` (ECS console or `aws ecs describe-services`).

## Option 2: redeploy a previous image by digest

Selecting an earlier **task definition revision** does not roll anything back
in this setup. Every revision refers to the same mutable `:prod` tag, so
revision 41 and revision 42 resolve to the identical image. Roll back the
image instead.

1. List recent images, newest first:

   ```bash
   aws ecr describe-images \
     --repository-name portfolio-backend \
     --query 'reverse(sort_by(imageDetails,&imagePushedAt))[:5].[imageDigest,imageTags,imagePushedAt]' \
     --output table
   ```

2. Re-tag the last known good digest as `prod`:

   ```bash
   GOOD=sha256:...
   MANIFEST=$(aws ecr batch-get-image \
     --repository-name portfolio-backend \
     --image-ids imageDigest="$GOOD" \
     --query 'images[0].imageManifest' --output text)
   aws ecr put-image \
     --repository-name portfolio-backend \
     --image-tag prod --image-manifest "$MANIFEST"
   ```

3. Force a new deployment and wait for it:

   ```bash
   aws ecs update-service --cluster <cluster> --service <service> --force-new-deployment
   aws ecs wait services-stable --cluster <cluster> --services <service>
   ```

Note that the services have `deployment_circuit_breaker` with `rollback = true`,
so a deployment that never reaches a steady state is reverted automatically.
This procedure is for the case where the new version starts cleanly but is
wrong.


## After rollback

- Confirm alarms return to OK (CloudWatch) and `/health` and the UI work.
- Investigate the bad deploy (logs, diff) and fix before deploying again.
