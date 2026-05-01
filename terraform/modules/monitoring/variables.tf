variable "prometheus_stack_chart_version" {
  description = "Helm chart version for kube-prometheus-stack"
  type        = string
  default     = "70.4.2"
}

variable "loki_chart_version" {
  description = "Helm chart version for Loki (standalone, monolithic mode)"
  type        = string
  default     = "6.55.0"
}

variable "alloy_chart_version" {
  description = "Helm chart version for Grafana Alloy (log collection agent)"
  type        = string
  default     = "0.12.5"
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  sensitive   = true
}