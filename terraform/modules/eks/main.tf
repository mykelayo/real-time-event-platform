module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name            = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id                          = var.vpc_id
  subnet_ids                      = var.private_subnet_ids
  control_plane_subnet_ids        = var.private_subnet_ids
  endpoint_public_access          = true
  endpoint_private_access         = true

  enabled_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler",
  ]

  enable_irsa                              = true

  cloudwatch_log_group_retention_in_days = 30
  cloudwatch_log_group_class             = "STANDARD"

  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    main = {
      name           = "${var.cluster_name}-ng"
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"
      subnet_ids     = var.private_subnet_ids

      desired_size = var.desired_node_count
      min_size     = var.min_node_count
      max_size     = var.max_node_count

      update_config = { max_unavailable = 1 }

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 20
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }

      iam_role_additional_policies = {
        ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }

      tags = merge(var.tags, {
        Name = "${var.cluster_name}-node"
      })
    }
  }

  tags = var.tags
}

module "ebs_csi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

module "aws_load_balancer_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name                              = "${var.cluster_name}-aws-lbc"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

resource "time_sleep" "wait_for_eks" {
  create_duration = "120s"
  depends_on      = [module.eks]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = var.lbc_chart_version

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = module.aws_load_balancer_controller_irsa_role.iam_role_arn
      }
    }
    region       = var.aws_region
    vpcId        = var.vpc_id
    replicaCount = var.desired_node_count
  })]

  depends_on = [
    module.eks,
    module.aws_load_balancer_controller_irsa_role,
    time_sleep.wait_for_eks
  ]
}

resource "aws_eks_access_entry" "admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.admin_role_arn
  type          = "STANDARD"

  tags = var.tags
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = var.admin_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}