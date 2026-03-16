variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "eks_cluster_endpoint" {
  type = string
}

variable "eks_cluster_ca_certificate" {
  type = string
}

variable "grafana_admin_password" {
  description = "Grafana admin password - em prod usar Secrets Manager"
  type        = string
  default     = "changeme-P@ss2024!"
  sensitive   = true
}

variable "enable_persistent_storage" {
  description = "Ativar PVCs para Prometheus e Grafana (desativar em dev para poupar custos)"
  type        = bool
  default     = true
}

variable "prometheus_retention_days" {
  type    = number
  default = 15
}

variable "prometheus_storage_size" {
  description = "Tamanho do PVC do Prometheus"
  type        = string
  default     = "50Gi"
}