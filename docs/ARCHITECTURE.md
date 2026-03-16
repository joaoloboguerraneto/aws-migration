# Architecture Decision Record

## 1. Network Design (VPC)

### CIDR Plan

| Subnet Type | AZ-a | AZ-b | Purpose |
|-------------|------|------|---------|
| Public | 10.0.1.0/24 | 10.0.2.0/24 | ALB, NAT Gateway |
| Private | 10.0.10.0/24 | 10.0.20.0/24 | EKS worker nodes |
| Data | 10.0.100.0/24 | 10.0.200.0/24 | RDS, ElastiCache |

### Why three subnet tiers?
- **Public subnets** have a route to the Internet Gateway — only ALB and NAT Gateway reside here.
- **Private subnets** route outbound traffic through NAT Gateway — EKS nodes live here. No direct inbound internet access.
- **Data subnets** have no internet route at all — database and cache are fully isolated. Only the private subnets can reach them via Security Groups.

This follows the **defense-in-depth** principle: even if an attacker compromises a pod, they cannot reach the database without traversing a Security Group boundary.

---

## 2. Compute — Why EKS over EC2?

| Criteria | EC2 (like current) | EKS |
|----------|-------------------|-----|
| Scaling | Manual / ASG | HPA + Cluster Autoscaler |
| Deployment | SSH + scripts | Declarative manifests |
| Self-healing | Limited | Pod restart, node replacement |
| Resource efficiency | Fixed allocation | Bin-packing across pods |
| Observability | Per-instance agents | Centralized with Prometheus |

Given the company already runs nginx web servers, containerizing the application and running it on Kubernetes provides a natural upgrade path while enabling horizontal scaling, rolling deployments, and built-in health checks.

### Node groups
- **System node group**: 2× `t3.medium` (monitoring, ingress controller, CoreDNS)
- **Application node group**: 2-6× `t3.large` (auto-scaled based on CPU/memory)
- Nodes spread across AZ-a and AZ-b for redundancy

---

## 3. Database — RDS MySQL Multi-AZ

### Why RDS over self-managed MySQL on EC2?
- **Automated failover**: Multi-AZ standby is promoted within 60-120 seconds
- **Automated backups**: Daily snapshots + point-in-time recovery (35-day retention)
- **Encryption**: KMS-managed keys for at-rest encryption, SSL for in-transit
- **Maintenance**: Automated patching during maintenance windows
- **Monitoring**: Enhanced monitoring + Performance Insights

### Migration path
Use **AWS Database Migration Service (DMS)** for:
1. Full load of existing data
2. Continuous replication (CDC) during migration window
3. Cutover with minimal downtime

---

## 4. Load Balancing — ALB + WAF

The physical firewall/load balancer is replaced by:
- **ALB** in public subnets — Layer 7 routing, health checks, sticky sessions
- **WAF** attached to ALB — OWASP Top 10 rule set, rate limiting, geo-blocking
- **ACM certificate** — Free TLS termination at the ALB

The ALB integrates natively with EKS via the AWS Load Balancer Controller, which creates ALB target groups from Kubernetes Ingress resources.

---

## 5. Observability — Replacing Nagios

| Current (Nagios) | Target |
|-------------------|--------|
| CPU/Memory/Disk/Load | Prometheus node_exporter + kube-state-metrics |
| Local log files | CloudWatch Logs via Fluent Bit |
| Email alerts | Grafana alerts → Slack/PagerDuty |
| Agent-based | Pull-based (Prometheus) + push (CloudWatch) |

### Stack
- **Prometheus**: Metrics collection from all pods and nodes
- **Grafana**: Dashboards and alerting
- **Fluent Bit**: Log aggregation to CloudWatch Logs
- **CloudWatch**: AWS service metrics (RDS, ALB, EKS control plane)

---

## 6. Content Delivery

- **CloudFront** distribution in front of ALB for dynamic content caching
- **S3 bucket** for static assets (JS, CSS, images) served via CloudFront
- **Route 53** for DNS with health check-based failover routing

---

## 7. Cost Optimization Notes

- Use **Spot instances** for dev/staging EKS node groups (up to 70% savings)
- Use **Reserved Instances** for production RDS
- **S3 Intelligent-Tiering** for backups and logs
- **Right-sizing** via CloudWatch Container Insights recommendations
- Single NAT Gateway in dev, Multi-AZ NAT in production