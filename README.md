`**README.md**`

# Real-Time Event-Driven Microservices Platform

An event-driven microservices platform on AWS EKS. Events are received
by an API gateway, streamed through Apache Kafka, persisted to PostgreSQL,
cached in Redis, pushed live to browsers over WebSocket and deployed
via GitOps with ArgoCD.

## Architecture

| Component        | Technology                       |
|------------------|----------------------------------|
| API Gateway      | Flask (Python 3.13)              |
| Event Producer   | Python + kafka-python            |
| Stream Processor | Python + kafka-python + psycopg2 |
| WebSocket Server | Node.js 22 + ws                  |
| Message Broker   | Apache Kafka (Strimzi on K8s)    |
| Cache            | Redis (Bitnami Helm chart)       |
| Database         | PostgreSQL 16 (AWS RDS)          |
| Orchestration    | AWS EKS (Kubernetes 1.32)        |
| IaC              | Terraform >= 1.7                 |
| GitOps           | ArgoCD + Kustomize               |
| CI/CD            | GitHub Actions                   |
| Monitoring       | Prometheus + Grafana + Loki      |

## How it works

Client → api-gateway → Kafka → stream-processor → PostgreSQL → Redis → websocket-server → Client

```

`event-producer` runs as a background worker generating synthetic events
so the pipeline stays active without needing real client t raffic.

## Prerequisites

- AWS CLI configured with EKS, RDS, VPC, ECR, and IAM permissions
- Terraform >= 1.7
- kubectl
- kustomize >= 5.4
- make

## Quick Start

```bash
# 1. Configure Terraform variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform.tfvars — fill in db_password, github_org, github_repo

# 2. Provision all infrastructure and deploy
make deploy

# 3. Port-forward services for local access
make port-forward

# 4. Run a load test
make load-test
```

`make deploy` provisions VPC, EKS, RDS, Redis, Kafka, ArgoCD, and
monitoring in one shot — then waits for ArgoCD to sync all application
services to the cluster automatically.

## CI/CD Pipeline

Defined in `.github/workflows/ci.yml`. All jobs run on every push to `main`.
`build-and-push` only runs after lint, security-scan, and test all pass.

```
push to main
  ├── lint          ruff (Python), eslint (Node.js)
  ├── security-scan Trivy IaC scan + pip-audit
  └── test          pytest (Python services), jest (websocket-server)
        │
        └── all pass → build-and-push
              ├── builds and pushes images to ECR (tagged with commit SHA)
              ├── updates kubernetes/overlays/dev/kustomization.yaml
              └── commits manifest [skip ci] → ArgoCD syncs to EKS
```

### Required GitHub secret


| Secret         | Description                                     |
| -------------- | ----------------------------------------------- |
| `AWS_ROLE_ARN` | IAM role ARN for GitHub Actions OIDC federation |


## GitOps with ArgoCD

ArgoCD watches `kubernetes/overlays/dev` on `main`. When CI commits
updated image tags, ArgoCD detects the change and syncs the cluster
within 3 minutes — no manual `kubectl apply` needed.

```bash
# Get the ArgoCD admin password
make argocd-password

# Open the ArgoCD UI at http://localhost:8088
make argocd-ui
```

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
```

## After first deploy — set the RDS hostname

```bash
# Get the RDS endpoint from Terraform output
terraform -chdir=terraform output -raw db_endpoint

# Paste it into kubernetes/overlays/dev/configmap-patch.yaml
# under POSTGRES_HOST, then commit and push — ArgoCD picks it up
```

## Monitoring

Grafana, Prometheus, and Loki are deployed in the `monitoring` namespace.

```bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80
# open http://localhost:3000  username: admin  password: grafana_admin_password
```

## Cleanup

```bash
make cleanup
```

Deletes all Kubernetes resources via ArgoCD, waits for load balancers
to deprovision, then runs `terraform destroy` to remove all AWS infrastructure.