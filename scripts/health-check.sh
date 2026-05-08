#!/bin/bash
set -euo pipefail

NAMESPACE="real-time-platform"
ARGOCD_NS="argocd"
PROJECT_NAME="real-time-platform"

pass() { echo "OK"; }
fail() { echo "FAILED"; }

check_deployment() {
  local namespace=$1
  local name=$2
  local available
  available=$(kubectl get deployment "$name" -n "$namespace" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
  local desired
  desired=$(kubectl get deployment "$name" -n "$namespace" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
  [ "${available:-0}" -ge 1 ] && [ "${available:-0}" -eq "${desired:-1}" ]
}

check_statefulset() {
  local namespace=$1
  local name=$2
  local ready
  ready=$(kubectl get statefulset "$name" -n "$namespace" \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  [ "${ready:-0}" -ge 1 ]
}

echo "Application (namespace: $NAMESPACE)..."
echo -n "  api-gateway:      "; check_deployment "$NAMESPACE" api-gateway      && pass || fail
echo -n "  event-producer:   "; check_deployment "$NAMESPACE" event-producer   && pass || fail
echo -n "  stream-processor: "; check_deployment "$NAMESPACE" stream-processor && pass || fail
echo -n "  websocket-server: "; check_deployment "$NAMESPACE" websocket-server && pass || fail

echo ""
echo "Kafka (namespace: kafka)..."
echo -n "  Strimzi operator: "; check_deployment kafka strimzi-cluster-operator && pass || fail
KAFKA_READY=$(kubectl get kafka event-cluster -n kafka \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
echo -n "  Kafka cluster:    "
[ "$KAFKA_READY" = "True" ] && pass || fail

echo ""
echo "Redis (namespace: redis)..."
echo -n "  redis-master:     "; check_statefulset redis redis-master && pass || fail

echo ""
echo "Monitoring (namespace: monitoring)..."
echo -n "  Prometheus:       "; check_deployment monitoring \
  "$(kubectl get deployment -n monitoring -o name 2>/dev/null | grep prometheus-server | head -1 | cut -d/ -f2 || echo prometheus)" \
  && pass || fail
echo -n "  Grafana:          "; check_deployment monitoring \
  "$(kubectl get deployment -n monitoring -o name 2>/dev/null | grep grafana | head -1 | cut -d/ -f2 || echo grafana)" \
  && pass || fail

echo ""
echo "ArgoCD (namespace: $ARGOCD_NS)..."
echo -n "  argocd-server:    "; check_deployment "$ARGOCD_NS" argocd-server     && pass || fail
echo -n "  repo-server:      "; check_deployment "$ARGOCD_NS" argocd-repo-server && pass || fail

echo ""
echo "ArgoCD application status..."
SYNC_STATUS=$(kubectl get application "$PROJECT_NAME" -n "$ARGOCD_NS" \
  -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
HEALTH_STATUS=$(kubectl get application "$PROJECT_NAME" -n "$ARGOCD_NS" \
  -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
echo "  Sync:   $SYNC_STATUS"
echo "  Health: $HEALTH_STATUS"

echo ""
echo "API Gateway health endpoint..."
echo -n "  /health:          "
HTTP_CODE=$(kubectl run "health-probe-$$" \
  --image=curlimages/curl:latest --restart=Never -i --rm --quiet \
  -n "$NAMESPACE" -- \
  curl -s -o /dev/null -w "%{http_code}" \
  "http://api-gateway.$NAMESPACE:5000/health" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then pass; else echo "HTTP $HTTP_CODE"; fi

echo ""
echo "Health check complete."
