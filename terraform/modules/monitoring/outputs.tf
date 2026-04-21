output "namespace" {
  description = "Namespace the monitoring stack is installed in"
  value       = kubernetes_namespace_v1.monitoring.metadata[0].name
}

output "grafana_password_command" {
  description = "Command to retrieve the Grafana admin password from the cluster"
  value       = "kubectl get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d"
}