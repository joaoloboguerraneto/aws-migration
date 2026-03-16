# AWS Cloud Migration

Projeto desenvolvido para o desafio técnico para a posição de DevOps Engineer.

## Contexto

A empresa tem uma aplicação web/mobile a correr num datacenter on-premises com a seguinte stack:
- 2 servidores web (nginx) atrás de um firewall físico que faz load balancing
- 1 base de dados MySQL sem replicação
- Nagios para monitorização básica (CPU, memória, disco)
- Sem disaster recovery, sem redundância

O objectivo é migrar para AWS com foco em redundância e alta disponibilidade.

## O que fiz

Desenhei e implementei uma arquitectura AWS completa com Infrastructure as Code. Em vez de só fazer o diagrama, decidi ir mais longe e criar toda a infra funcional com Terraform, uma aplicação de exemplo em Go, CI/CD com GitHub Actions e monitorização com Prometheus/Grafana.

### Estrutura do projecto

```
.
├── app/                    # Aplicação Go (cronómetro + relógio)
│   ├── main.go
│   ├── Dockerfile
│   └── go.mod
├── charts/app/             # Helm chart para deploy no K8s
├── terraform/
│   ├── VPC/                # Rede com 3 camadas de subnets
│   ├── EKS/                # Cluster Kubernetes
│   ├── RDS/                # MySQL Multi-AZ
│   ├── ALB/                # Load balancer + WAF
│   ├── ECR/                # Registry de imagens Docker
│   ├── monitoring/         # Prometheus + Grafana via Helm
│   ├── S3/                 # Backend do Terraform state
│   └── environments/       # Configurações por ambiente (dev/stg/prd)
├── docs/                   # Documentação técnica
└── .github/workflows/      # Pipelines CI/CD
```

## Arquitectura AWS

Cada componente on-premises tem um equivalente gerido na AWS:

| On-premises | AWS | Porquê |
|-------------|-----|--------|
| Firewall/LB | ALB + WAF | Layer 7, health checks, protecção OWASP |
| 2x nginx | EKS (Kubernetes) | Auto-scaling, self-healing, rolling deploys |
| MySQL (single) | RDS Multi-AZ | Failover automático em ~60s, backups diários |
| Nagios | Prometheus + Grafana + CloudWatch | Métricas de containers, dashboards, alertas |
| — | Route 53 + CloudFront | DNS com failover, CDN na edge |

### Rede

Optei por 3 camadas de subnets seguindo o princípio de defence-in-depth:

- **Public** (10.0.1.0/24, 10.0.2.0/24) — só o ALB e o NAT Gateway ficam aqui, expostos à internet
- **Private** (10.0.10.0/24, 10.0.20.0/24) — os worker nodes do EKS, sem acesso directo da internet
- **Data** (10.0.100.0/24, 10.0.200.0/24) — RDS e ElastiCache, totalmente isolados, sem rota para a internet

O tráfego só flui numa direcção: internet > ALB (public) > pods (private) > base de dados (data). Cada transição é controlada por Security Groups.

### Kubernetes (EKS)

Escolhi EKS em vez de EC2 puro porque a empresa já tem 2 web servers o passo natural é containerizar e orquestrar. Com Kubernetes ganhamos:
- HPA para escalar pods com base em CPU/memória
- Rolling updates sem downtime
- Self-healing (pods que crasham são recriados)
- Topology spread para distribuir pods entre AZs

### Base de dados

RDS MySQL com Multi-AZ resolve o maior ponto de falha da arquitectura actual uma única instância de MySQL sem replicação. Com Multi-AZ, se a instância primária falhar, o failover para a standby demora 60-120 segundos e é automático.

Configurei também:
- Encriptação at-rest com KMS (chave gerida)
- SSL obrigatório nas conexões (require_secure_transport = 1)
- Enhanced Monitoring + Performance Insights
- Backups automáticos com retenção configurável por ambiente

### Segurança

Tentei cobrir as três áreas que o desafio pede:

**Encriptação at-rest** — KMS para RDS, EBS volumes, ECR e Secrets Manager

**Encriptação in-transit** — TLS no ALB (via ACM), SSL forçado no RDS, HTTPS entre CloudFront e ALB

**IAM** — O pipeline usa OIDC federation em vez de access keys estáticas. O GitHub Actions troca um JWT token por credenciais temporárias da AWS. Zero segredos armazenados.

## CI/CD

O pipeline está dividido em dois workflows:

**terraform.yaml** — Gere a infraestrutura. Quando faço push de alterações na pasta `terraform/`, detecta qual ambiente mudou e faz `terraform apply`. Também tem opção manual para destroy.

**ci.yaml** — Gerei a aplicação. Quando altero código na pasta `app/`:
1. Corre os testes Go
2. Builda a imagem Docker
3. Faz scan de vulnerabilidades com Trivy
4. Push para o ECR
5. Deploy no EKS via `helm upgrade`

O deploy para produção tem um approval gate — alguém precisa de aprovar manualmente no GitHub antes de avançar.

### Autenticação

Não uso access keys no GitHub. Em vez disso:
- O módulo `terraform/S3/github-oidc` cria um OIDC provider na AWS e um IAM Role
- A trust policy só aceita tokens vindos deste repositório específico
- O único secret no GitHub é o ARN desse role

## Monitorização

O kube-prometheus-stack é instalado automaticamente pelo Terraform via Helm provider. Inclui:
- Prometheus para colecta de métricas
- Grafana com dashboards pré-configurados (cluster, nodes, pods)
- Alertmanager para routing de alertas
- node-exporter nos nós (substitui as métricas do Nagios)
- kube-state-metrics para métricas do Kubernetes

## Aplicação

Criei uma aplicação simples em Go com dois features, um cronómetro e um relógio para demonstrar o pipeline completo. Tem:
- API REST (start/stop/reset/lap)
- Web UI responsiva
- Endpoints de health (/healthz, /readyz) para os probes do Kubernetes
- Dockerfile multi-stage com imagem distroless (segurança)
- Corre como non-root (UID 65534)

## Helm Chart

O deploy da aplicação é feito via Helm chart próprio (`charts/app/`) com templates para:
- Deployment (rolling update, topology spread, security context)
- Service, Ingress (ALB annotations)
- HPA, PDB
- Secret / ExternalSecret (para integração com AWS Secrets Manager)
- ServiceAccount (com IRSA annotation)
- ServiceMonitor (descoberta automática pelo Prometheus)
- NetworkPolicy

Os valores variam por ambiente — dev usa menos recursos e réplicas, prod usa mais.

## Estratégia de migração

Detalho isto nos docs mas em resumo propus 3 fases:

1. **Híbrido** — On-prem como primário, AWS como failover via Route 53 + DMS replication
2. **Cutover** — Janela de manutenção (~10 min), promover RDS, switch DNS
3. **Optimização** — CloudFront, auto-scaling, Reserved Instances, decommission on-prem

## Como correr

```bash
# 1. Bootstrap (S3 + DynamoDB para state)
cd terraform/S3/backend && terraform init && terraform apply

# 2. OIDC para GitHub Actions
cd terraform/S3/github-oidc && terraform apply

# 3. Configurar GitHub secret AWS_ROLE_ARN

# 4. Push → pipeline faz o resto
git push origin main

# 5. Aceder ao cluster
aws eks update-kubeconfig --name aws-challenge-dev --region us-east-1
kubectl port-forward svc/stopwatch-stopwatch-app -n stopwatch-dev 8080:80
```

## Decisões que tomei

- **EKS em vez de ECS** — mais flexível, portável, e permite demonstrar Helm/monitoring de forma mais completa
- **Helm em vez de kubectl apply** — templates reutilizáveis, rollback fácil, values por ambiente
- **OIDC em vez de IAM keys** — best practice actual, sem rotação de credenciais
- **t3.micro para dev** — conta free tier, em prod seria t3.large ou maior
- **3 tiers de subnets** — mais seguro que o típico public/private, isola completamente a camada de dados