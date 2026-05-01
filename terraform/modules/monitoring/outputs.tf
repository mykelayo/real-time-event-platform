output "namespace" {
  description = "Namespace the monitoring stack is installed in"
  value       = kubernetes_namespace_v1.monitoring.metadata[0].name
}

output "grafana_service" {
  description = "Grafana service name for port-forwarding"
  value       = "kube-prometheus-stack-grafana"
}

output "loki_endpoint" {
  description = "Loki push endpoint (in-cluster)"
  value       = "http://loki.monitoring:3100/loki/api/v1/push"
}