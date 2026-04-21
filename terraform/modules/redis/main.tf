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
  version    = "19.6.4"
  wait       = true
  timeout    = 300

  values = [yamlencode({
    architecture = "standalone"

    auth = {
      enabled  = false
    }

    master = {
      persistence = {
        # For production set enabled = true and provide a storageClass.
        enabled = false
      }
      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "250m", memory = "256Mi" }
      }
    }
  })]

  depends_on = [kubernetes_namespace_v1.redis]
}