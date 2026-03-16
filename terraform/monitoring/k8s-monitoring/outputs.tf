output "grafana_namespace" {
  value = kubernetes_namespace.monitoring.metadata[0].name
}

output "grafana_access" {
  value = var.environment == "prod" ? "LoadBalancer (check: kubectl get svc -n monitoring monitoring-grafana)" : "kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
}

output "prometheus_access" {
  value = "kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090"
}