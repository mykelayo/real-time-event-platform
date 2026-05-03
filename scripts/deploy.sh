#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

AWS_REGION="us-east-1"
NAMESPACE="real-time-platform"
ARGOCD_NS="argocd"

echo "==> Provisioning infrastructure with Terraform"
cd "$PROJECT_ROOT/terraform"
terraform init

echo "==> Stage 1: Core infrastructure"
terraform apply -auto-approve \
  -target=module.networking \
  -target=module.ecr

echo "==> EKS cluster"
terraform apply -auto-approve \
  -target=module.eks

echo "==> Configuring kubectl"
CLUSTER_NAME=$(terraform output -raw cluster_name)
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "==> Waiting for EKS nodes to be ready"
kubectl wait node --all --for=condition=Ready --timeout=300s

echo "==> Stage 2: Installing Strimzi operator"
kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "https://github.com/strimzi/strimzi-kafka-operator/releases/download/0.43.0/strimzi-cluster-operator-0.43.0.yaml" -n kafka
kubectl wait deployment/strimzi-cluster-operator \
  --for=condition=available \
  --timeout=120s \
  -n kafka

# Stage 3: remaining Helm-based modules (ArgoCD, Redis, monitoring)
echo "==> Provisioning remaining infrastructure"
terraform apply -auto-approve \
  -target=module.argocd \
  -target=module.redis

# Stage 4: Kafka CRD resources, Strimzi must be ready first
echo "==> Importing existing kafka namespace into Terraform state"
cd "$PROJECT_ROOT/terraform"
terraform import module.kafka.kubernetes_namespace_v1.kafka kafka 2>/dev/null || true

echo "==> Applying Kafka cluster resources"
terraform apply -auto-approve \
  -target=module.kafka

# Stage 5: everything else
echo "==> Final apply"
terraform apply -auto-approve

echo "==> Waiting for Strimzi operator to be ready"
kubectl wait deployment/strimzi-cluster-operator \
  --for=condition=available \
  --timeout=300s \
  -n kafka

echo "==> Waiting for Kafka cluster to be ready"
kubectl wait kafka/event-cluster \
  --for=condition=Ready \
  --timeout=600s \
  -n kafka

echo "==> Waiting for Redis to be ready"
kubectl wait statefulset/redis-master \
  --for=condition=Ready \
  --timeout=180s \
  -n redis

echo "==> Waiting for ArgoCD to be ready"
kubectl wait deployment/argocd-server \
  --for=condition=available \
  --timeout=300s \
  -n "$ARGOCD_NS"

echo "==> Triggering ArgoCD hard refresh"
kubectl annotate application real-time-platform \
  -n "$ARGOCD_NS" \
  argocd.argoproj.io/refresh=hard \
  --overwrite

echo "==> Waiting for application pods to be ready"
kubectl wait deployment --all \
  --for=condition=available \
  --timeout=300s \
  -n "$NAMESPACE"

echo ""
echo "Deployment complete."
echo "Run 'make argocd-ui' to open the ArgoCD dashboard."
echo "Run 'make port-forward' to access services locally."