# Security Design

## Network Security

### Subnet Isolation

Traffic flow is strictly controlled through Security Groups and NACLs:

```
Internet → IGW → Public Subnets (ALB only)
                      │
                 Security Group: allow 443 from 0.0.0.0/0
                      │
              Private Subnets (EKS nodes)
                      │
                 Security Group: allow app-port from ALB SG only
                      │
               Data Subnets (RDS, ElastiCache)
                      │
                 Security Group: allow 3306/6379 from EKS SG only
```

### Security Group Rules

| SG Name | Inbound | Source |
|---------|---------|--------|
| `sg-alb` | 443 (HTTPS) | 0.0.0.0/0 |
| `sg-eks-nodes` | App port | `sg-alb` |
| `sg-eks-nodes` | 10250 (kubelet) | `sg-eks-nodes` |
| `sg-rds` | 3306 (MySQL) | `sg-eks-nodes` |
| `sg-redis` | 6379 (Redis) | `sg-eks-nodes` |

All other traffic is **denied by default**.

---

## Encryption

### At-Rest
| Resource | Encryption | Key Management |
|----------|-----------|----------------|
| RDS MySQL | AES-256 | AWS KMS (CMK) |
| EBS volumes (EKS nodes) | AES-256 | AWS KMS (CMK) |
| S3 buckets | SSE-S3 / SSE-KMS | AWS KMS |
| ECR images | AES-256 | AWS KMS |
| Secrets Manager | AES-256 | AWS KMS (CMK) |

### In-Transit
| Path | Protocol | Certificate |
|------|----------|-------------|
| User → CloudFront | TLS 1.2+ | ACM |
| CloudFront → ALB | TLS 1.2+ | ACM |
| ALB → EKS pods | TLS 1.2+ | ACM / self-signed |
| EKS → RDS | TLS (force SSL) | RDS CA bundle |
| EKS → ElastiCache | TLS | ElastiCache in-transit |

---

## Identity & Access Management

### IRSA (IAM Roles for Service Accounts)

Instead of embedding AWS credentials in pods, each Kubernetes ServiceAccount is mapped to an IAM Role via OIDC federation:

```hcl
# Example: App pod needs S3 read access
module "app_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  
  role_name = "app-s3-reader"
  
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:app-sa"]
    }
  }
  
  role_policy_arns = {
    s3 = "arn:aws:iam::policy/app-s3-read-only"
  }
}
```

### Principle of Least Privilege

- EKS nodes: minimal IAM role (ECR pull, CloudWatch logs, EBS CSI)
- Application pods: only the permissions they need via IRSA
- CI/CD: separate IAM user with scoped permissions per environment
- Terraform: assumes role with admin permissions, MFA required

---

## WAF Configuration

AWS WAF is attached to the ALB with the following rule groups:

1. **AWS Managed Rules — Common Rule Set**: Blocks common exploits (XSS, SQLi, path traversal)
2. **AWS Managed Rules — Known Bad Inputs**: Blocks known malicious patterns
3. **Rate-based Rule**: Limits 2000 requests per 5 minutes per IP
4. **Geo-restriction**: (Optional) Allow only expected countries

---

## Container Security

- **Base image**: `gcr.io/distroless/static-debian12` — minimal attack surface
- **Trivy scanning**: Every image is scanned for CVEs before push to ECR
- **Read-only filesystem**: Pod `securityContext.readOnlyRootFilesystem: true`
- **Non-root user**: Containers run as UID 65534 (nobody)
- **No privilege escalation**: `allowPrivilegeEscalation: false`
- **Network Policies**: Only allow necessary pod-to-pod communication

---

## Secrets Management

Application secrets (DB credentials, API keys) are stored in **AWS Secrets Manager** and injected into pods via the **External Secrets Operator**:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: app-secrets
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: prod/app/database
        property: password
```

This avoids storing secrets in:
- Environment variables in manifests
- ConfigMaps
- Git repositories
- Docker images