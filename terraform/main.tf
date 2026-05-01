data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

module "networking" {
  source = "./modules/networking"

  project_name         = var.project_name
  environment          = var.environment
  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  tags                 = var.tags
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
  tags         = var.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = var.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  public_subnet_ids   = module.networking.public_subnet_ids
  node_instance_types = var.node_instance_types
  desired_node_count  = var.desired_node_count
  lbc_chart_version   = var.lbc_chart_version
  min_node_count      = var.min_node_count
  max_node_count      = var.max_node_count
  aws_region          = var.aws_region
  tags                = var.tags
}

module "kafka" {
  source = "./modules/kafka"

  cluster_name  = var.cluster_name
  kafka_version = var.kafka_version
  tags          = var.tags

  depends_on = [module.eks]
}

module "rds" {
  source = "./modules/rds"

  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = module.networking.vpc_id
  vpc_cidr                  = var.vpc_cidr
  private_subnet_ids        = module.networking.private_subnet_ids
  cluster_security_group_id = module.eks.cluster_security_group_id
  node_security_group_id    = module.eks.node_security_group_id
  db_username               = var.db_username
  db_password               = var.db_password
  tags                      = var.tags
}

module "monitoring" {
  source = "./modules/monitoring"

  grafana_admin_password         = var.grafana_admin_password
  prometheus_stack_chart_version = var.prometheus_stack_chart_version
  loki_chart_version             = var.loki_chart_version
  alloy_chart_version            = var.alloy_chart_version

  depends_on = [module.eks, module.kafka, module.redis]
}

module "redis" {
  source = "./modules/redis"
  tags   = var.tags

  depends_on = [module.eks]
}

module "argocd" {
  source = "./modules/argocd"

  project_name                 = var.project_name
  environment                  = var.environment
  github_org                   = var.github_org
  github_repo                  = var.github_repo
  github_token                 = var.github_token
  argocd_chart_version         = var.argocd_chart_version
  argocd_admin_password_bcrypt = var.argocd_admin_password_bcrypt
  argocd_webhook_secret        = var.argocd_webhook_secret
  tags                         = var.tags

  depends_on = [module.eks]
}