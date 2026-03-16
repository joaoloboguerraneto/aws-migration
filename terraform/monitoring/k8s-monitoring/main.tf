resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      environment                     = var.environment
    }
  }
}

# ─────────────────────────────────────────────
# Helm Release - kube-prometheus-stack
# ─────────────────────────────────────────────
resource "helm_release" "kube_prometheus_stack" {
  name       = "monitoring"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.2.2"

  timeout = 900
  wait    = false

  # ─── Prometheus ────────────────────────────
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "${var.prometheus_retention_days}d"
  }

  set {
    name  = "prometheus.prometheusSpec.resources.requests.cpu"
    value = "50m"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.limits.cpu"
    value = "200m"
  }
  set {
    name  = "prometheus.prometheusSpec.resources.limits.memory"
    value = "512Mi"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec"
    value = ""
  }

  set {
    name  = "grafana.resources.requests.cpu"
    value = "50m"
  }
  set {
    name  = "grafana.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "alertmanager.enabled"
    value = "false"
  }

  set {
    name  = "nodeExporter.enabled"
    value = "false"
  }

  # Persistent storage
  dynamic "set" {
    for_each = var.enable_persistent_storage ? [1] : []
    content {
      name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName"
      value = "gp3"
    }
  }

  dynamic "set" {
    for_each = var.enable_persistent_storage ? [1] : []
    content {
      name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
      value = var.prometheus_storage_size
    }
  }

  # Scrape todos os namespaces
  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  # ─── Grafana ───────────────────────────────
  set {
    name  = "grafana.enabled"
    value = "true"
  }

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  set {
    name  = "grafana.persistence.enabled"
    value = var.enable_persistent_storage ? "true" : "false"
  }

  dynamic "set" {
    for_each = var.enable_persistent_storage ? [1] : []
    content {
      name  = "grafana.persistence.storageClassName"
      value = "gp3"
    }
  }

  dynamic "set" {
    for_each = var.enable_persistent_storage ? [1] : []
    content {
      name  = "grafana.persistence.size"
      value = "10Gi"
    }
  }

  set {
    name  = "grafana.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "grafana.resources.requests.memory"
    value = "256Mi"
  }

  # Dashboards da comunidade
  set {
    name  = "grafana.dashboards.default.kubernetes-cluster.gnetId"
    value = "7249"
  }

  set {
    name  = "grafana.dashboards.default.kubernetes-cluster.datasource"
    value = "Prometheus"
  }

  set {
    name  = "grafana.dashboards.default.node-exporter.gnetId"
    value = "1860"
  }

  set {
    name  = "grafana.dashboards.default.node-exporter.datasource"
    value = "Prometheus"
  }

  # Grafana service type - LoadBalancer em prod, ClusterIP em dev/staging
  set {
    name  = "grafana.service.type"
    value = var.environment == "prod" ? "LoadBalancer" : "ClusterIP"
  }

  # ─── Alertmanager ──────────────────────────
  set {
    name  = "alertmanager.enabled"
    value = "true"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "alertmanager.alertmanagerSpec.resources.requests.memory"
    value = "64Mi"
  }

  # ─── Node Exporter (substitui Nagios) ─────
  set {
    name  = "nodeExporter.enabled"
    value = "true"
  }

  # ─── kube-state-metrics ────────────────────
  set {
    name  = "kubeStateMetrics.enabled"
    value = "true"
  }

  depends_on = [kubernetes_namespace.monitoring]
}
