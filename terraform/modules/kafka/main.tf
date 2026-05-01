terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

resource "kubernetes_namespace_v1" "kafka" {
  metadata {
    name   = "kafka"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

/* resource "helm_release" "strimzi" {
  name       = "strimzi"
  repository = "https://strimzi.io/charts"
  chart      = "strimzi-kafka-operator"
  namespace  = kubernetes_namespace_v1.kafka.metadata[0].name
  version    = "0.43.0"
  atomic           = true      
  cleanup_on_fail  = true      
  wait             = true      
  timeout          = 120
  replace          = true       

  values = [
    <<-YAML
      watchNamespaces:
        - kafka
    YAML
  ]

  depends_on = [kubernetes_namespace_v1.kafka]
}

resource "time_sleep" "wait_for_strimzi_crd" {
  create_duration = "90s"
  depends_on      = [helm_release.strimzi]
} */

resource "kubectl_manifest" "kafka_node_pool" {
  yaml_body = <<-YAML
    apiVersion: kafka.strimzi.io/v1beta2
    kind: KafkaNodePool
    metadata:
      name: combined
      namespace: kafka
      labels:
        strimzi.io/cluster: event-cluster
    spec:
      replicas: 3
      roles:
        - controller
        - broker
      storage:
        type: ephemeral
        # NOTE: for production, switch to:
        # type: persistent-claim
        # size: 10Gi
        # deleteClaim: false
  YAML

  depends_on = [kubernetes_namespace_v1.kafka]
}

resource "kubectl_manifest" "kafka_cluster" {
  yaml_body = <<-YAML
    apiVersion: kafka.strimzi.io/v1beta2
    kind: Kafka
    metadata:
      name: event-cluster
      namespace: kafka
      annotations:
        strimzi.io/node-pools: enabled
        strimzi.io/kraft: enabled
    spec:
      kafka:
        version: "${var.kafka_version}"
        metadataVersion: "3.7-IV4"
        listeners:
          - name: plain
            port: 9092
            type: internal
            tls: false
        config:
          offsets.topic.replication.factor: 3
          transaction.state.log.replication.factor: 3
          transaction.state.log.min.isr: 2
          default.replication.factor: 3
          min.insync.replicas: 2
      entityOperator:
        topicOperator: {}
        userOperator: {}
  YAML

  depends_on = [kubectl_manifest.kafka_node_pool]
}

resource "kubectl_manifest" "kafka_topic" {
  yaml_body = <<-YAML
    apiVersion: kafka.strimzi.io/v1beta2
    kind: KafkaTopic
    metadata:
      name: user-events
      namespace: kafka
      labels:
        strimzi.io/cluster: event-cluster
    spec:
      partitions: 10
      replicas: 3
      config:
        retention.ms: 604800000
        segment.bytes: 1073741824
  YAML

  depends_on = [kubectl_manifest.kafka_cluster]
}