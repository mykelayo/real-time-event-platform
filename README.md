# Real-Time Event-Driven Microservices Platform

An event-driven microservices platform on AWS EKS. Events are received by an API gateway, streamed through Apache Kafka, persisted to PostgreSQL, cached in Redis, and pushed live to browsers over WebSocket. Deployed via GitOps with ArgoCD.

## Architecture

| Component        | Technology                         |
|------------------|------------------------------------|
| API Gateway      | Flask (Python 3.13)                |
| Event Producer   | Python + kafka-python              |
| Stream Processor | Python + kafka-python + psycopg2   |
| WebSocket Server | Node.js 22 + ws                    |
| Message Broker   | Apache Kafka 3.7 (Strimzi, KRaft)  |
| Cache            | Redis (Bitnami Helm chart)         |
| Database         | PostgreSQL 16 (AWS RDS)            |
| Container Registry | AWS ECR (immutable tags)         |
| Orchestration    | AWS EKS (Kubernetes 1.32)          |
| IaC              | Terraform >= 1.7                   |
| GitOps           | ArgoCD + Kustomize                 |
| CI/CD            | GitHub Actions                     |
| Monitoring       | Prometheus + Grafana + Loki        |

## How it works

```
Client → api-gateway → Kafka → stream-processor → PostgreSQL → Redis → websocket-server → Client
```

Each component is a separate microservice with a single responsibility:

- **api-gateway** — receives HTTP POST events from clients and publishes them to Kafka
- **event-producer** — background worker that generates synthetic events to keep the pipeline active without real client traffic. In production this would be removed; the api-gateway is the sole Kafka producer
- **stream-processor** — Kafka consumer that persists every event to PostgreSQL and increments per-event-type counters in Redis
- **websocket-server** — reads Redis counters every second and pushes live updates to all connected browser clients over a persistent WebSocket connection

Kafka decouples producers from consumers — the api-gateway publishes and moves on regardless of how fast the stream-processor can consume. If the processor is slow or crashes, events queue durably in Kafka and are replayed from the last committed offset on restart.

## Prerequisites

- AWS CLI configured with EKS, RDS, VPC, ECR, and IAM permissions
- Terraform >= 1.7
- kubectl
- kustomize >= 5.4
- make
- htpasswd (for generating the ArgoCD admin password hash)

## Quick Start

```bash
# 1. Copy and fill in non-sensitive Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform.tfvars — set github_org, github_repo 

# 2. Export sensitive variables — do not write these to terraform.tfvars
export TF_VAR_db_username="appuser"
export TF_VAR_db_password="yourpassword"
export TF_VAR_redis_password="yourpassword"
export TF_VAR_grafana_admin_password="yourpassword"
export TF_VAR_github_token="ghp_..."
export TF_VAR_argocd_webhook_secret="yourwebhooksecret"

# 3. Generate and export the ArgoCD admin password bcrypt hash
export TF_VAR_argocd_admin_password_bcrypt=$(htpasswd -nbBC 10 '' yourpassword | tr -d ':\n' | sed 's/$2y/$2a/')

# 4. Provision all infrastructure and deploy
make deploy

# 5. Port-forward services for local access
make port-forward

# 6. Run a load test
make load-test
```

`make deploy` provisions VPC, EKS, ECR, RDS, Redis, Kafka, ArgoCD, and monitoring in one shot — then waits for ArgoCD to sync all application services to the cluster.

## Secrets

Kubernetes secrets (PostgreSQL credentials) are not stored in this repository. Before the first deploy, create the secret manually in the cluster:

```bash
kubectl create secret generic app-secrets \
  --namespace real-time-platform \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_PASSWORD=yourpassword
```

Terraform stores the full RDS credentials automatically in AWS Secrets Manager at `real-time-platform-db-credentials-dev`. The production path is to replace the manual step above with the External Secrets Operator (ESO) pulling from Secrets Manager — see `kubernetes/base/secrets.yaml` for the placeholder and wiring.

## After first deploy — set the RDS hostname

The RDS endpoint is not known until after Terraform runs. Once it is:

```bash
# Get the endpoint
terraform -chdir=terraform output -raw db_endpoint

# Paste it into kubernetes/overlays/dev/configmap-patch.yaml
# under POSTGRES_HOST, then commit and push — ArgoCD picks it up automatically
```

## Infrastructure

All AWS infrastructure is managed by Terraform under `terraform/`. The module layout is:

| Module       | What it provisions                                         |
|--------------|------------------------------------------------------------|
| networking   | VPC, public/private subnets, NAT gateways, route tables    |
| eks          | EKS cluster, managed node group, IRSA, CloudWatch logging  |
| ecr          | ECR repositories for all four services (immutable tags)    |
| rds          | PostgreSQL 16 on RDS, subnet group, security group         |
| redis        | Redis via Bitnami Helm chart in the `redis` namespace      |
| kafka        | Strimzi operator + KRaft Kafka cluster + `user-events` topic |
| argocd       | ArgoCD, repo credentials, Application resource             |
| monitoring   | kube-prometheus-stack + Loki via Helm                      |

ECR repositories are created with `image_tag_mutability = IMMUTABLE` — the same SHA tag cannot be pushed twice, which enforces the GitOps guarantee that a tag always refers to the same image.

## CI/CD Pipeline

Defined in `.github/workflows/ci.yml`. All jobs run on every push to `main` and every pull request targeting `main` or `develop`. `build-and-push` only runs after lint, security-scan, and test all pass.

```
push to main
  ├── lint          ruff (Python), eslint (Node.js)
  ├── security-scan Trivy IaC scan + pip-audit
  └── test          pytest (Python services), jest (websocket-server)
        │
        └── all pass → build-and-push
              ├── builds each image and pushes to ECR (SHA-only tag, no :latest)
              ├── scans each built image with Trivy — stops on HIGH/CRITICAL CVEs
              ├── updates kubernetes/overlays/dev/kustomization.yaml with new tags
              └── commits manifest [skip ci] → ArgoCD syncs to EKS
```

### Required GitHub secret

| Secret         | Description                                      |
| -------------- | ------------------------------------------------ |
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions OIDC federation  |

## GitOps with ArgoCD

ArgoCD watches `kubernetes/overlays/dev` on `main`. When CI commits updated image tags, ArgoCD detects the change and syncs the cluster — no manual `kubectl apply` needed. Sync retries automatically with exponential backoff if a resource isn't ready yet.

```bash
# Get the ArgoCD admin password
make argocd-password

# Open the ArgoCD UI at http://localhost:8088
make argocd-ui
```

ArgoCD is configured with:
- `prune: true` — removes resources deleted from the repo
- `selfHeal: true` — reverts manual cluster changes back to the repo state
- `ServerSideApply: true` — avoids annotation size limits on large resources
- `ApplyOutOfSyncOnly: true` — only touches resources that actually changed

## Makefile reference

```bash
make deploy            # full provision + deploy (start here)
make cleanup           # destroy everything (prompts for confirmation)

make terraform-plan    # preview infrastructure changes
make terraform-apply   # apply changes with interactive approval
make kubeconfig        # configure kubectl for the cluster

make status            # pod status across all namespaces
make logs SVC=api-gateway  # tail logs for a specific service

make argocd-password   # print ArgoCD admin password
make argocd-ui         # port-forward ArgoCD to localhost:8088
make port-forward      # port-forward all services locally
make load-test         # fire 100 test events at the API
make health-check      # full health check
```

## Monitoring

Grafana, Prometheus, and Loki are deployed in the `monitoring` namespace by Terraform.

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# open http://localhost:3000
# username: admin
# password: the value you set for TF_VAR_grafana_admin_password
```

Prometheus discovers `ServiceMonitor` resources across all namespaces including `real-time-platform`. Loki collects logs from all pods via Promtail and is pre-wired as a Grafana datasource.

## Cleanup

```bash
make cleanup
```

Deletes the ArgoCD Application (which cascades to all managed Kubernetes resources via the finalizer), waits for load balancers to deprovision, then runs `terraform destroy` to remove all AWS infrastructure.