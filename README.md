# AWS Cloud Migration

## 📋 Overview

This project proposes a **complete cloud migration strategy** from a single on-premises datacenter to AWS, addressing the company's need for **redundancy, high availability, and scalability**.

### Current State (On-Premises)
- 2 web servers (nginx) behind a physical firewall/load balancer
- 1 MySQL database (no replication)
- Nagios monitoring (CPU, memory, disk, load)
- No disaster recovery, no redundancy
- Single point of failure at every layer

### Target State (AWS)
- Multi-AZ EKS cluster with auto-scaling
- RDS MySQL Multi-AZ with automated failover
- Application Load Balancer with WAF
- Full observability stack (Prometheus + Grafana + CloudWatch)
- Infrastructure as Code (Terraform)
- CI/CD with GitHub Actions
- Encryption at-rest and in-transit

---

## 🏗️ Architecture

```
                    ┌─────────────┐
                    │   Route 53  │
                    │ + CloudFront│
                    │   + WAF     │
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │   Application Load      │
              │      Balancer           │
              │   (Public Subnets)      │
              └────────────┬────────────┘
                           │
         ┌─────────────────┴─────────────────┐
         │         EKS Cluster               │
         │      (Private Subnets)            │
         │                                   │
         │  ┌──────────┐  ┌──────────┐       │
         │  │ Node AZ-a│  │ Node AZ-b│       │
         │  │ App Pods  │  │ App Pods │       │
         │  └──────────┘  └──────────┘       │
         │                                   │
         │  ┌─────────────────────────┐      │
         │  │ Prometheus + Grafana    │      │
         │  └─────────────────────────┘      │
         └───────────────┬───────────────────┘
                         │
         ┌───────────────┴───────────────┐
         │     Data Subnets (Isolated)   │
         │                               │
         │  ┌─────────┐  ┌───────────┐   │
         │  │RDS MySQL│  │ElastiCache│   │
         │  │Multi-AZ │  │  Redis    │   │
         │  └─────────┘  └───────────┘   │
         └───────────────────────────────┘
```

See `docs/` for detailed architecture diagrams.

---

## 📁 Project Structure

```
.
├── README.md                          # This file
├── docs/                              # Architecture documentation
│   ├── ARCHITECTURE.md                # Detailed architecture decisions
│   ├── MIGRATION_STRATEGY.md          # Migration plan & hybrid strategy
│   └── SECURITY.md                    # Security design
├── terraform/                         # Infrastructure as Code
│   ├── modules/                       # Reusable Terraform modules
│   │   ├── vpc/                       # VPC, subnets, NAT, IGW
│   │   ├── eks/                       # EKS cluster & node groups
│   │   ├── rds/                       # RDS MySQL Multi-AZ
│   │   ├── alb/                       # ALB + WAF + ACM
│   │   ├── ecr/                       # Container registry
│   │   └── monitoring/                # CloudWatch alarms & dashboards
│   └── environments/                  # Per-environment configurations
│       ├── dev/                       # Development account
│       ├── staging/                   # Staging account
│       └── prod/                      # Production account
├── app/                               # Go application (stopwatch)
│   ├── main.go                        # Application source code
│   ├── go.mod                         # Go module definition
│   ├── Dockerfile                     # Multi-stage Docker build
│   └── README.md                      # App documentation
├── k8s/                               # Kubernetes manifests (Kustomize)
│   ├── base/                          # Base manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── ingress.yaml
│   │   ├── hpa.yaml
│   │   └── kustomization.yaml
│   └── overlays/                      # Per-environment patches
│       ├── dev/
│       ├── staging/
│       └── prod/
├── monitoring/                        # Observability stack
│   ├── prometheus-values.yaml         # Prometheus Helm chart values
│   ├── grafana-values.yaml            # Grafana Helm chart values
│   └── alerts.yaml                    # Alerting rules
└── .github/workflows/                 # CI/CD pipelines
    ├── ci.yaml                        # Build, test, scan, push
    └── cd.yaml                        # Deploy to EKS per environment
```

---

## 🔧 AWS Services Used

| Service | Purpose | Replaces |
|---------|---------|----------|
| **VPC** | Network isolation with public/private/data subnets | Physical network |
| **EKS** | Managed Kubernetes for container orchestration | Bare-metal web servers |
| **RDS MySQL** | Managed database with Multi-AZ failover | Single MySQL server |
| **ALB** | Layer 7 load balancing with health checks | Physical firewall/LB |
| **CloudFront** | CDN for static assets and edge caching | — |
| **Route 53** | DNS management with health checks and failover | — |
| **WAF** | Web Application Firewall rules | Physical firewall |
| **ECR** | Private Docker registry | — |
| **ElastiCache** | Redis for session management | — |
| **S3** | Static assets, backups, Terraform state | Local disk |
| **KMS** | Encryption key management (at-rest) | — |
| **Secrets Manager** | Database credentials, API keys | Config files |
| **CloudWatch** | Centralized logging and metrics | Nagios |
| **ACM** | TLS certificates (in-transit encryption) | — |
| **NAT Gateway** | Outbound internet for private subnets | — |

---

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured with appropriate profiles
- Terraform >= 1.6
- kubectl
- Docker
- Go >= 1.22

### 1. Deploy Infrastructure (Dev)

```bash
cd terraform/environments/dev
terraform init
terraform plan
terraform apply
```

### 2. Build & Push Application

```bash
cd app
docker build -t stopwatch-app:latest .
# Tag and push to ECR (see CI/CD pipeline)
```

### 3. Deploy to Kubernetes

```bash
kubectl apply -k k8s/overlays/dev/
```

### 4. Install Monitoring

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  -f monitoring/prometheus-values.yaml \
  -n monitoring --create-namespace
```

---

## 🔒 Security Highlights

- **Network segmentation**: Public subnets (ALB, NAT), Private subnets (EKS), Data subnets (RDS, ElastiCache)
- **Encryption at-rest**: KMS-managed keys for RDS, EBS, S3, ECR
- **Encryption in-transit**: TLS 1.2+ via ACM certificates on ALB, mutual TLS between pods
- **Secrets management**: AWS Secrets Manager integrated with EKS via External Secrets Operator
- **IAM**: IRSA (IAM Roles for Service Accounts) — no static credentials
- **WAF**: OWASP Top 10 rule set on CloudFront/ALB
- **Security scanning**: Trivy image scanning in CI pipeline

---

## 🔄 CI/CD Strategy

The deployment pipeline uses **GitHub Actions** with separate workflows for CI and CD:

1. **CI** (on push/PR): Lint → Test → Build Docker image → Scan with Trivy → Push to ECR
2. **CD** (on merge to main/release branches): Terraform plan/apply → Kustomize deploy to EKS

Environment promotion follows: `dev` → `staging` → `prod` with manual approval gates for production.

---

## 🔀 Hybrid / Partial Migration Strategy

For a phased approach where on-prem remains active with cloud failover:

1. **AWS Site-to-Site VPN** or **Direct Connect** between on-prem and VPC
2. **Route 53 failover routing** with health checks on the on-prem endpoint
3. **RDS as read replica** of on-prem MySQL (via DMS), promoted on failover
4. Cloud environment stays warm (reduced capacity) until failover triggers

See `docs/MIGRATION_STRATEGY.md` for the complete plan.

---

## 📄 License

This project was created as part of the DevOps Engineer recruitment process.