# Real-Time Event-Driven Microservices Platform

An event-driven microservices platform on AWS EKS. Events are received by an API gateway, streamed through Apache Kafka, persisted to PostgreSQL, cached in Redis, and pushed live to browsers over WebSocket. Deployed via GitOps with ArgoCD.

## Architecture

| Component          | Technology                                      |
|--------------------|-------------------------------------------------|
| API Gateway        | Flask (Python 3.13)                             |
| Event Producer     | Python + kafka-python-ng                        |
| Stream Processor   | Python + kafka-python-ng + psycopg2             |
| WebSocket Server   | Node.js 22 + ws                                 |
| Message Broker     | Apache Kafka 3.7 (Strimzi 0.43.0, KRaft mode)  |
| Cache              | Redis 8.x (Bitnami Helm chart, ECR Public)      |
| Database           | PostgreSQL 16 (AWS RDS)                         |
| Container Registry | AWS ECR (immutable tags)                        |
| Orchestration      | AWS EKS 1.32 (managed node group, c7i-flex.large) |
| IaC                | Terraform                                        |
| GitOps             | ArgoCD + Kustomize                              |
| CI/CD              | GitHub Actions (OIDC)                           |
| Monitoring         | kube-prometheus-stack + Loki                     |

## How it works

```
Client → api-gateway → Kafka → stream-processor → PostgreSQL → Redis → websocket-server → Client
```

Each component is a separate microservice with a single responsibility:

- **api-gateway** — receives HTTP POST events from clients and publishes them to Kafka
- **event-producer** — background worker that generates synthetic events to keep the pipeline active without real client traffic. In production this would be removed; the api-gateway is the sole Kafka producer
- **stream-processor** — Kafka consumer that persists every event to PostgreSQL and increments per-event-type counters in Redis
- **websocket-server** — reads Redis counters every second and pushes live updates to all connected browser clients over a persistent WebSocket connection

Kafka decouples producers from consumers, the api-gateway publishes and moves on regardless of how fast the stream-processor can consume. If the processor is slow or crashes, events queue durably in Kafka and are replayed from the last committed offset on restart.

## Prerequisites

- AWS CLI configured with permissions for EKS, RDS, VPC, ECR, IAM, and Secrets Manager
- Terraform >= 1.7
- kubectl
- kustomize >= 5.4
- helm >= 3.x
- make
- htpasswd (for generating the ArgoCD admin password hash — part of `apache2-utils` on Debian/Ubuntu)

## Quick Start

```bash
# 1. Copy and fill in non-sensitive Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform.tfvars — set github_org, github_repo

# 2. Export sensitive variables

export AWS_ACCESS_KEY_ID="youraccesskeyid"
export AWS_SECRET_ACCESS_KEY="yoursecretaccesskey"
export TF_VAR_db_username="appuser"
export TF_VAR_db_password="yourpassword"
export TF_VAR_redis_password="yourpassword"
export TF_VAR_grafana_admin_password="yourpassword"
export TF_VAR_github_token="ghp_..."
export TF_VAR_argocd_webhook_secret="yourwebhooksecret"
export TF_VAR_admin_role_arn="youradminrolearn"

# 3. Generate and export the ArgoCD admin password bcrypt hash
export TF_VAR_argocd_admin_password_bcrypt=$(htpasswd -nbBC 10 '' yourpassword | tr -d ':\n' | sed 's/$2y/$2a/')

# 4. Provision all infrastructure and deploy
make deploy

# 5. After deploy completes, set the RDS hostname (see section below)

# 6. Port-forward services for local access
make port-forward

# 7. Run a load test
make load-test
```

`make deploy` runs in stages: provisions VPC and EKS first, installs the Strimzi operator directly via kubectl, then provisions Redis, ArgoCD, Kafka CRD resources, and monitoring then waits for ArgoCD to sync all application services to the cluster.

## Secrets

Kubernetes secrets (PostgreSQL credentials) are not stored in this repository. Before the first deploy, create the secret manually in the cluster:

```bash
kubectl create secret generic app-secrets \
  --namespace real-time-platform \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_PASSWORD=yourpassword
```

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

| Module     | What it provisions                                                        |
|------------|---------------------------------------------------------------------------|
| networking | VPC, public/private subnets, NAT gateways, route tables                   |
| eks        | EKS 1.32 cluster, managed node group, IRSA roles, CloudWatch logging, ALB controller |
| ecr        | ECR repositories for all four services (immutable tags)                   |
| rds        | PostgreSQL 16 on RDS, subnet group, security group, Secrets Manager secret |
| redis      | Redis via Bitnami Helm chart (ECR Public registry)                        |
| kafka      | Kafka namespace + KafkaNodePool + Kafka cluster + `user-events` topic (Strimzi installed separately) |
| argocd     | ArgoCD, repo credentials, Application resource                            |
| monitoring | kube-prometheus-stack 70.4.2, Loki      |

ECR repositories are created with `image_tag_mutability = IMMUTABLE`, the same SHA tag cannot be pushed twice, which enforces the GitOps guarantee that a tag always refers to the same image.

### Strimzi operator install

The Strimzi operator is installed directly via kubectl rather than through Terraform's Helm provider, this is handled automatically by `make deploy` and `make terraform-apply`. The Kafka CRD resources (KafkaNodePool, Kafka cluster, KafkaTopic) are still managed by Terraform via the `kubectl` provider and depend on the operator being ready.

```bash
# Strimzi is installed at version 0.43.0
kubectl apply -f "https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.43.0/strimzi-cluster-operator-0.43.0.yaml" -n kafka
```

### Redis image source

Redis is configured to pull from ECR Public Gallery (`public.ecr.aws/bitnami/redis`) which has no rate limits within AWS infrastructure.

The `terraform-apply` target stages the apply, networking and ECR are provisioned first, then EKS separately. 

## CI/CD Pipeline

Defined in `.github/workflows/ci.yml`. All jobs run on every push to `main` and every pull request targeting `main` or `develop`. `build-and-push` only runs after lint, security-scan, and test all pass.

```
push to main
  ├── lint          ruff (Python), eslint (Node.js)
  ├── security-scan Trivy IaC config scan + pip-audit
  └── test          pytest (Python services), jest (websocket-server)
        │
        └── all pass → build-and-push
              ├── authenticates to AWS via OIDC
              ├── builds each image and pushes to ECR (SHA-only tag, no :latest)
              ├── scans each built image with Trivy, fails on HIGH/CRITICAL CVEs
              ├── updates kubernetes/overlays/dev/kustomization.yaml with new tags
              └── commits manifest [skip ci] → ArgoCD syncs to EKS
```

### Required GitHub secrets

| Secret         | Description                                                        |
|----------------|--------------------------------------------------------------------|
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions OIDC federation                    |

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
make terraform-apply   # staged apply — networking/ECR, then EKS, then everything else
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

Prometheus discovers `ServiceMonitor` resources across all namespaces. Application services expose metrics at `/metrics` which Prometheus scrapes automatically.

## Cleanup

```bash
make cleanup
```

Deletes the ArgoCD Application (cascading to all managed Kubernetes resources), uninstalls Helm releases and CRDs for Strimzi and monitoring, waits for load balancers to deprovision, then runs `terraform destroy` in stages: app-level resources first, EKS second, networking and ECR last. This ordering prevents ENIs and security groups from blocking VPC deletion.