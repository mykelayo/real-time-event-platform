resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.prometheus_stack_chart_version
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [yamlencode({
    grafana = {
      adminPassword = var.grafana_admin_password
      service = {
        type = "ClusterIP"
      }
      sidecar = {
        datasources = {
          defaultDatasourceEnabled = true
        }
        dashboards = {
          enabled = true
          label   = "grafana_dashboard"
        }
      }
    }

    prometheus = {
      prometheusSpec = {
        retention                      = "7d"
        serviceMonitorSelectorNilUsesHelmValues = false
      }
    }
  })]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

resource "helm_release" "loki_stack" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  version          = var.loki_stack_chart_version
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 300

  values = [yamlencode({
    grafana = {
      enabled = false
    }
    promtail = {
      enabled = true
    }
    loki = {
      persistence = {
        enabled      = false
        size         = "5Gi"
        storageClass = ""
      }
    }
  })]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    helm_release.kube_prometheus_stack,
  ]
}