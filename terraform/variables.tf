variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "real-time-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "rt-platform"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.32"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "node_instance_types" {
  description = "EC2 instance types for node group"
  type        = list(string)
  default     = ["c7i-flex.large"]
}

variable "desired_node_count" {
  description = "Desired number of nodes"
  type        = number
  default     = 3
}

variable "min_node_count" {
  description = "Minimum number of nodes"
  type        = number
  default     = 3
}

variable "max_node_count" {
  description = "Maximum number of nodes"
  type        = number
  default     = 10
}

variable "lbc_chart_version" {
  description = "Helm chart version for AWS Load Balancer Controller"
  type        = string
  default     = "1.8.1"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL master password"
  type        = string
  sensitive   = true
}

variable "kafka_version" {
  description = "Kafka version"
  type        = string
  default     = "3.7.0"
}

variable "prometheus_stack_chart_version" {
  description = "Helm chart version for kube-prometheus-stack"
  type        = string
  default     = "70.4.2"
}

variable "grafana_admin_password" {
  description = "Grafana admin dashboard password"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub organisation or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "real-time-event-platform"
}

variable "github_token" {
  description = "GitHub token for ArgoCD repo access"
  type        = string
  sensitive   = true
  default     = ""
}

variable "argocd_chart_version" {
  description = "Helm chart version for ArgoCD"
  type        = string
  default     = "7.4.4"
}

variable "argocd_admin_password_bcrypt" {
  description = "Bcrypt hash of the ArgoCD admin password"
  type        = string
  sensitive   = true
}

variable "argocd_webhook_secret" {
  description = "GitHub webhook secret for ArgoCD"
  type        = string
  sensitive   = true
  default     = ""
}

variable "loki_chart_version" {
  description = "Helm chart version for Loki"
  type        = string
  default     = "6.55.0"
}

variable "alloy_chart_version" {
  description = "Helm chart version for Grafana Alloy"
  type        = string
  default     = "0.12.5"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "real-time-platform"
  }
}