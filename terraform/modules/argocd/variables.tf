variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "github_org" {
  description = "GitHub organisation or username that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token for ArgoCD repo access (needed for private repos)"
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
  description = "Bcrypt hash of the ArgoCD admin password — generate with: htpasswd -nbBC 10 '' yourpassword | tr -d ':\\n' | sed 's/$2y/$2a/'"
  type        = string
  sensitive   = true
}

variable "argocd_webhook_secret" {
  description = "Secret token configured in the GitHub webhook for this repo"
  type        = string
  sensitive   = true
  default     = ""
}

variable "target_revision" {
  description = "Git branch ArgoCD tracks"
  type        = string
  default     = "main"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
}