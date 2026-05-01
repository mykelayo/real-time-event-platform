output "cluster_name" {
    description = "EKS cluster name"
    value = module.eks.cluster_name
}
output "cluster_endpoint" { 
    description = "EKS cluster endpoint"
    value = module.eks.cluster_endpoint
    sensitive = true
}
output "cluster_certificate_authority_data" { 
    description = "EKS cluster certificate authority data"
        value = module.eks.cluster_certificate_authority_data
    sensitive = true
}
output "oidc_provider_arn"                  {
    description = "EKS OIDC provider ARN"
    value = module.eks.oidc_provider_arn
}
output "cluster_security_group_id"          {
    description = "EKS cluster security group ID"
    value = module.eks.cluster_security_group_id
}
output "node_security_group_id" {
    description = "EKS node security group ID"
    value = module.eks.node_security_group_id
}