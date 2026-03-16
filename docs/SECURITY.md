# Segurança

Tentei organizar a segurança em camadas — se uma falha, a próxima segura.

## Rede

O princípio é simples: só expor o mínimo necessário.

As subnets públicas só têm o ALB e o NAT Gateway. Os worker nodes do EKS ficam em subnets privadas não têm IP público, o tráfego de saída passa pelo NAT. A base de dados e o cache ficam em subnets isoladas que nem sequer têm rota para a internet.

Os Security Groups controlam quem fala com quem:

| SG | Permite | Origem |
|----|---------|--------|
| ALB | porta 443 | 0.0.0.0/0 (internet) |
| EKS nodes | porta da app | só o SG do ALB |
| RDS | porta 3306 | só o SG dos EKS nodes |

Tudo o resto é negado por omissão.

Activei também VPC Flow Logs para CloudWatch dá visibilidade sobre o tráfego de rede para troubleshooting e auditorias.

## Encriptação

### At-rest

Tudo o que armazena dados está encriptado:
- RDS AES-256 com chave KMS gerida (CMK com rotação automática)
- EBS volumes dos nodes mesma abordagem
- S3 buckets SSE-KMS
- ECR images encriptação por omissão
- Secrets Manager KMS

### In-transit

- Utilizadores > CloudFront/ALB TLS 1.2+ com certificados ACM (grátis)
- ALB > pods pode ser HTTP dentro da VPC ou HTTPS se quisermos end-to-end
- Pods > RDS SSL obrigatório (require_secure_transport = 1 no parameter group)
- Pods > ElastiCache TLS activado na configuração do cluster

## Identidade e acessos

### No pipeline (CI/CD)

Não uso access keys estáticas no GitHub. Em vez disso, configurei OIDC federation:

1. O módulo `github-oidc` cria um OpenID Connect provider na AWS
2. Um IAM Role com trust policy que só aceita tokens JWT do repositório específico
3. Quando o workflow corre, o GitHub pede um token ao OIDC provider
4. A AWS valida o token e devolve credenciais temporárias

Resultado: o único secret no GitHub é o ARN do role. Sem chaves para rodar, sem risco de leak.

### No cluster (IRSA)

Os pods não usam credenciais da instância EC2. Cada ServiceAccount do Kubernetes pode ser mapeado para um IAM Role via IRSA (IAM Roles for Service Accounts). Assim cada pod tem exactamente as permissões que precisa nada mais.

### Secrets da aplicação

Em dev/staging, os secrets ficam em Kubernetes Secrets normais (criados pelo Helm chart). Em produção, uso o External Secrets Operator que puxa os segredos do AWS Secrets Manager assim os secrets nunca são commitados em Git nem ficam em variáveis de ambiente visíveis.

## WAF

O AWS WAF está associado ao ALB com 3 regras:
- **Common Rule Set** — bloqueia XSS, SQLi, path traversal e os ataques mais frequentes
- **SQL Injection Rule Set** — regras adicionais específicas para SQLi
- **Rate limiting** — máximo 2000 requests por IP em 5 minutos, depois bloqueia

## Containers

A imagem Docker da aplicação usa:
- Base distroless (gcr.io/distroless) sem shell, sem package manager, superfície de ataque mínima
- Multi-stage build o Go binary é compilado numa imagem com toolchain e depois copiado para a imagem final limpa
- Non-root corre como UID 65534
- Read-only filesystem não consegue escrever em disco
- Trivy scan no CI todas as imagens são verificadas antes de ir para o ECR

No Kubernetes, o security context do pod reforça tudo isto:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65534
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```