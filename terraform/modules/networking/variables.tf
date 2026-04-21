variable "project_name" {
    description = "Project name"
    type = string
}
variable "environment"  {
    description = "Environment"
    type = string
}
variable "vpc_cidr"     {
    description = "VPC CIDR"
    type = string
}
variable "availability_zones"   {
    description = "Availability zones"
    type = list(string)
}
variable "public_subnet_cidrs"  {
    description = "Public subnet CIDRs"
    type = list(string)
}
variable "private_subnet_cidrs" {
    description = "Private subnet CIDRs"
    type = list(string)
}

variable "cluster_name" { 
    description = "EKS cluster name for ALB discovery" 
    type = string 
}

variable "tags" {
    description = "Tags"
    type = map(string)
}
