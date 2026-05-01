#!/bin/bash
set -euo pipefail

NAMESPACE="real-time-platform"
ARGOCD_NS="argocd"

cleanup() {
  echo "Stopping port-forwards..."
  kill "$API_PID" "$WS_PID" "$ARGO_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> Port-forwarding api-gateway     → localhost:5000"
kubectl port-forward svc/api-gateway -n "$NAMESPACE" 5000:5000 &
API_PID=$!

echo "==> Port-forwarding websocket-server → localhost:8080"
kubectl port-forward svc/websocket-server -n "$NAMESPACE" 8080:8080 &
WS_PID=$!

echo "==> Port-forwarding argocd-server    → localhost:8088"
kubectl port-forward svc/argocd-server -n "$ARGOCD_NS" 8088:80 &
ARGO_PID=$!

echo ""
echo "Services available:"
echo "  API Gateway:    http://localhost:5000"
echo "  WebSocket:      ws://localhost:8080"
echo "  ArgoCD UI:      http://localhost:8088"
echo ""
echo "Press Ctrl+C to stop all port-forwards."

wait "$API_PID" "$WS_PID" "$ARGO_PID"