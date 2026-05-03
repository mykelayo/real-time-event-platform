#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ARGOCD_NS="argocd"
NAMESPACE="real-time-platform"
PROJECT_NAME="real-time-platform"

echo "WARNING: This will delete all Kubernetes resources and destroy all AWS infrastructure."
read -rp "Type 'yes' to continue: " confirm

if [ "$confirm" != "yes" ]; then
  echo "Cancelled."
  exit 0
fi

cd "$PROJECT_ROOT/terraform"

# Remove ArgoCD Application CRs from Terraform state first
echo "==> Removing ArgoCD Application resources from Terraform state..."
terraform state rm "module.argocd.kubernetes_manifest.argocd_app" 2>/dev/null || true
terraform state rm module.argocd.kubectl_manifest.argocd_app 2>/dev/null || true

# Let ArgoCD cascade-delete managed resources before pulling the cluster
echo "==> Deleting ArgoCD Application (triggers managed resource cleanup)..."
kubectl delete application "$PROJECT_NAME" -n "$ARGOCD_NS" \
  --ignore-not-found --wait=false 2>/dev/null || true

echo "==> Waiting for application namespace to drain..."
kubectl wait namespace/"$NAMESPACE" --for=delete --timeout=180s 2>/dev/null || true

# Delete ingress so ALB controller releases the load balancer before VPC destroy
echo "==> Deleting ingress to release ALB..."
kubectl delete ingress -n "$NAMESPACE" --all --ignore-not-found 2>/dev/null || true

echo "==> Waiting 60s for ALB and load balancers to deprovision..."
sleep 60

echo "==> Uninstalling Strimzi..."
kubectl delete kafka --all -n kafka --ignore-not-found 2>/dev/null || true
kubectl delete kafkanodepool --all -n kafka --ignore-not-found 2>/dev/null || true
helm uninstall strimzi -n kafka --ignore-not-found 2>/dev/null || true
STRIMZI_CRDS=$(kubectl get crd 2>/dev/null | grep strimzi | awk '{print $1}')
if [ -n "$STRIMZI_CRDS" ]; then
  kubectl delete crd $STRIMZI_CRDS --ignore-not-found 2>/dev/null || true
fi

# Uninstall Helm releases so finalizers don't block namespace deletion
echo "==> Uninstalling monitoring stack..."
helm uninstall loki -n monitoring --ignore-not-found 2>/dev/null || true
helm uninstall kube-prometheus-stack -n monitoring --ignore-not-found 2>/dev/null || true
sleep 15

echo "==> Uninstalling ArgoCD..."
helm uninstall argocd -n "$ARGOCD_NS" --ignore-not-found 2>/dev/null || true

# Remove CRDs — Helm uninstall does not delete CRDs by default
echo "==> Removing ArgoCD CRDs..."
kubectl delete crd \
  applications.argoproj.io \
  applicationsets.argoproj.io \
  appprojects.argoproj.io \
  --ignore-not-found 2>/dev/null || true

echo "==> Removing monitoring CRDs..."
kubectl delete crd \
  alertmanagerconfigs.monitoring.coreos.com \
  alertmanagers.monitoring.coreos.com \
  podmonitors.monitoring.coreos.com \
  probes.monitoring.coreos.com \
  prometheuses.monitoring.coreos.com \
  prometheusrules.monitoring.coreos.com \
  servicemonitors.monitoring.coreos.com \
  thanosrulers.monitoring.coreos.com \
  --ignore-not-found 2>/dev/null || true

# Force-clear finalizers and delete namespaces
echo "==> Cleaning up namespaces..."
for ns in "$NAMESPACE" monitoring "$ARGOCD_NS" kafka redis; do
  echo "    deleting namespace: $ns"
  kubectl patch namespace "$ns" \
    -p '{"metadata":{"finalizers":[]}}' \
    --type=merge --ignore-not-found 2>/dev/null || true
  kubectl delete namespace "$ns" --ignore-not-found --wait=false 2>/dev/null || true
done

echo "==> Waiting for namespaces to terminate..."
for ns in "$NAMESPACE" monitoring "$ARGOCD_NS" kafka redis; do
  kubectl wait --for=delete namespace/"$ns" --timeout=90s 2>/dev/null || true
done

# Staged destroy — app resources first, then cluster, then network
echo "==> Destroying app-level Terraform resources..."
terraform state rm module.eks.helm_release.aws_load_balancer_controller 2>/dev/null || true
terraform destroy \
  -target=module.monitoring \
  -target=module.argocd \
  -target=module.kafka \
  -target=module.redis \
  -target=module.rds \
  -auto-approve

echo "==> Destroying EKS cluster..."
terraform destroy \
  -target=module.eks \
  -auto-approve

echo "==> Destroying networking and ECR..."
terraform destroy \
  -target=module.networking \
  -target=module.ecr \
  -auto-approve

echo ""
echo "Cleanup complete."