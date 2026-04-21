variable "prometheus_stack_chart_version" {
  description = "Helm chart version for kube-prometheus-stack"
  type        = string
  default     = "70.4.2"
}

variable "loki_stack_chart_version" {
  description = "Helm chart version for loki-stack"
  type        = string
  default     = "2.10.2"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
}