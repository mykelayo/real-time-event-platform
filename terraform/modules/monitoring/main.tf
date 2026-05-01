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
      # Wire Loki in as an additional Grafana datasource
      additionalDataSources = [
        {
          name   = "Loki"
          type   = "loki"
          url    = "http://loki.monitoring:3100"
          access = "proxy"
        }
      ]
    }

    prometheus = {
      prometheusSpec = {
        retention = "7d"
        serviceMonitorSelectorNilUsesHelmValues = false
      }
    }
  })]

  depends_on = [kubernetes_namespace_v1.monitoring]
}

# Loki in monolithic / SingleBinary mode with filesystem storage.
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = var.loki_chart_version
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [yamlencode({
  deploymentMode = "SingleBinary"

  loki = {
    commonConfig = {
      replication_factor = 1
    }
    storage = {
      type = "filesystem"
    }
    schemaConfig = {
      configs = [
        {
          from         = "2024-04-01"
          store        = "tsdb"
          object_store = "filesystem"
          schema       = "v13"
          index = {
            prefix = "index_"
            period = "24h"
          }
        }
      ]
    }
    auth_enabled = false
  }

  singleBinary = {
    replicas = 1
  }

  read    = { replicas = 0 }
  write   = { replicas = 0 }
  backend = { replicas = 0 }

  chunksCache = {
    enabled = false
  }

  resultsCache = {
    enabled = false
  }

  lokiCanary = {
    enabled = false
  }

  test = {
    enabled = false
  }

  monitoring = {
    selfMonitoring = {
      enabled = false
      grafanaAgent = {
        installOperator = false
      }
    }
  }

  gateway = {
    enabled = false
  }
})]

  depends_on = [
    kubernetes_namespace_v1.monitoring,
    helm_release.kube_prometheus_stack,
  ]
}

# Grafana Alloy
# Runs as a DaemonSet, collects pod logs and ships to Loki.
resource "helm_release" "alloy" {
  name             = "alloy"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  version          = var.alloy_chart_version
  namespace        = kubernetes_namespace_v1.monitoring.metadata[0].name
  create_namespace = false
  wait             = false
  timeout          = 300

  values = [yamlencode({
    alloy = {
      configMap = {
        content = <<-ALLOY
          discovery.kubernetes "pods" {
            role = "pod"
          }

          discovery.relabel "pods" {
            targets = discovery.kubernetes.pods.targets

            rule {
              source_labels = ["__meta_kubernetes_pod_node_name"]
              target_label  = "__host__"
            }

            rule {
              source_labels = ["__meta_kubernetes_namespace"]
              target_label  = "namespace"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_name"]
              target_label  = "pod"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_container_name"]
              target_label  = "container"
            }

            rule {
              source_labels = ["__meta_kubernetes_pod_label_app"]
              target_label  = "app"
            }
          }

          loki.source.kubernetes "pods" {
            targets    = discovery.relabel.pods.output
            forward_to = [loki.write.default.receiver]
          }

          loki.write "default" {
            endpoint {
              url = "http://loki.monitoring:3100/loki/api/v1/push"
            }
          }
        ALLOY
      }
    }

    controller = {
      type = "daemonset"
    }
  })]

  depends_on = [helm_release.loki]
}