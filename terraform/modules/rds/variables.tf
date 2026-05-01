variable "project_name" {
     description = "Name of the project"
     type = string
     default = "real-time-platform"
}
variable "environment" {
     description = "Environment"
     type = string
     default = "dev"
}
variable "vpc_id" {
     description = "VPC ID"
     type = string
}

variable "vpc_cidr" {
     description = "VPC CIDR"
     type = string
}

variable "private_subnet_ids" {
     description = "Private subnet IDs"
     type = list(string)
}

variable "db_username" {
     description = "Username for the database"
     type = string
     sensitive = true
     default = ""
}
variable "db_password" {
     description = "Password for the database"
     type = string
     sensitive = true
     default = ""
}
variable "tags" {
     description = "Tags"
     type = map(string)
}
variable "cluster_security_group_id" {
  description = "Security group ID of the EKS cluster control plane"
  type        = string
}

variable "node_security_group_id" {
  description = "Security group ID of the EKS worker nodes"
  type        = string
}