output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN, needed to create IRSA roles for service accounts"
  value       = module.eks.oidc_provider_arn
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap address (in-cluster)"
  value       = module.kafka.kafka_bootstrap_servers
}

output "db_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "db_secret_arn" {
  description = "Secrets Manager ARN for DB credentials"
  value       = module.rds.secret_arn
}

output "kubeconfig_command" {
  description = "Run this after apply to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "redis_host" {
  description = "Redis service hostname (in-cluster)"
  value       = module.redis.redis_host
}

output "ecr_repository_urls" {
  description = "ECR repository URLs per service"
  value       = module.ecr.repository_urls
}