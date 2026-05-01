"#!/bin/bash
set -euo pipefail
check_pods() {
  local namespace=$1
  local label=$2
  local statuses
  statuses=$(kubectl get pods -n "$namespace" -l "$label" \
    -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
  if [ -z "$statuses" ]; then
    return 1
  fi
  for status in $statuses; do
    [ "$status" = "Running" ] || return 1
  done
  return 0
}
pass() { echo "OK"; }
fail() { echo "FAILED"; }
echo "Application..."
echo -n "Backend pods:   "; check_pods devops-app "app=backend"  && pass || fail
echo -n "Frontend pods:  "; check_pods devops-app "app=frontend" && pass || fail
echo ""
echo "Monitoring..."
echo -n "Prometheus:     "; check_pods monitoring "app.kubernetes.io/name=prometheus"     && pass || fail
echo -n "Grafana:        "; check_pods monitoring "app.kubernetes.io/name=grafana"        && pass || fail
echo -n "Loki:           "; check_pods monitoring "app=loki"                              && pass || fail
echo ""
echo "ArgoCD..."
echo -n "ArgoCD server:  "; check_pods argocd "app.kubernetes.io/name=argocd-server"     && pass || fail
echo -n "Repo server:    "; check_pods argocd "app.kubernetes.io/name=argocd-repo-server" && pass || fail
echo ""
echo "ArgoCD sync status..."
SYNC_STATUS=$(kubectl get application "$PROJECT_NAME" -n argocd \
  -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
HEALTH_STATUS=$(kubectl get application "$PROJECT_NAME" -n argocd \
  -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
echo "Sync:   $SYNC_STATUS"
echo "Health: $HEALTH_STATUS"
echo ""
echo "Backend API..."
echo -n "Health endpoint: "
HTTP_CODE=$(kubectl run "health-probe-$RANDOM" \
  --image=curlimages/curl --restart=Never -i --rm --quiet -- \
  curl -s -o /dev/null -w "%{http_code}" \
  http://backend.devops-app:5000/api/health 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then pass; else echo "$HTTP_CODE"; fi
echo ""
echo "Health check complete."' look at this and now create a health script for out project