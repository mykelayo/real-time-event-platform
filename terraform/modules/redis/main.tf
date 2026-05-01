resource "kubernetes_namespace_v1" "redis" {
  metadata {
    name   = "redis"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

resource "helm_release" "redis" {
  name       = "redis"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "redis"
  namespace  = kubernetes_namespace_v1.redis.metadata[0].name
  version    = "21.1.3" 
  wait       = true
  timeout    = 600

  values = [yamlencode({
    global = {
      security = {
        allowInsecureImages = true
      }
    }
    architecture = "standalone"
    auth         = { enabled = false }
    image = {
      registry   = "public.ecr.aws"
      repository = "bitnami/redis"
      tag        = "8.6.2-debian-12-r1"   # exists on ECR Public
    }
    master = {
      persistence = { enabled = false }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "250m", memory = "256Mi" }
      }
    }
    sysctlImage = { enabled = false }
  })]
}