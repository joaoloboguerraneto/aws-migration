# Arquitetura

## Rede (VPC)

O desenho da VPC segue o modelo de 3 camadas. A ideia é que cada camada só consegue falar com a camada adjacente nunca diretamente com uma camada que esteja 2 níveis acima ou abaixo.

### CIDR Plan

| Tipo | AZ-a | AZ-b | O que vive aqui |
|------|------|------|-----------------|
| Public | 10.0.1.0/24 | 10.0.2.0/24 | ALB, NAT Gateway |
| Private | 10.0.10.0/24 | 10.0.20.0/24 | Worker nodes do EKS |
| Data | 10.0.100.0/24 | 10.0.200.0/24 | RDS, ElastiCache |

As subnets de dados não têm rota para a internet nem de saída. Se um atacante comprometer um pod, não consegue chegar à base de dados sem passar pelo Security Group que só aceita tráfego vindo dos nodes do EKS na porta 3306.

### Flow de tráfego

```
User → Route 53 → CloudFront > ALB (public subnet)
                                  > Security Group
                              EKS pods (private subnet)
                                  > Security Group
                              RDS MySQL (data subnet)
```

## Porquê EKS

A empresa já corre 2 web servers com nginx containerizar é o passo natural. Com EKS ganhamos coisas que com EC2 + ASG teríamos de construir à mão:

- **Scaling granular** — o HPA escala pods individualmente em vez de instâncias inteiras. Se a app precisa de mais 200Mi de RAM, não preciso de lançar uma máquina nova de 4GB.
- **Self-healing** — se um processo crasha, o kubelet reinicia-o em segundos. Com EC2, dependemos do ASG que demora minutos.
- **Rolling updates** — `maxSurge: 1, maxUnavailable: 0` garante que nunca há downtime durante deploys.
- **Topology spread** — os pods ficam distribuídos entre AZs automaticamente.

Para dev uso t3.micro (free tier), para produção seria t3.large ou m5.large dependendo do workload.

### Node groups

Em produção teria dois node groups:
- **System** (2x t3.medium) para o monitoring stack, ingress controller, CoreDNS
- **Application** (2-6x t3.large, auto-scaled) para os pods da aplicação

Em dev, para poupar, uso um único node group com t3.micro.

## RDS MySQL

Este é talvez o componente mais crítico da migração. O setup actual tem um único MySQL sem replicação qualquer falha de disco ou de rede significa downtime e potencial perda de dados.

Com RDS Multi-AZ:
- A AWS mantém uma réplica síncrona noutra AZ
- Se a primária falhar, o failover é automático em 60-120 segundos
- O endpoint DNS não muda a aplicação nem nota

Configurei também backups automáticos (point-in-time recovery), slow query log, e Performance Insights para dar visibilidade ao DBA.

O `require_secure_transport = 1` no parameter group força todas as conexões a usar SSL nenhum dado viaja em claro entre a app e a base de dados.

## Load Balancing (ALB + WAF)

O firewall físico actual faz duas coisas: firewall e load balancing. Na AWS separei isto em dois serviços:

- **ALB** — faz o load balancing Layer 7, com health checks nos pods e sticky sessions se necessário
- **WAF** — protecção contra os ataques mais comuns (SQLi, XSS, path traversal) usando os managed rule sets da AWS, mais um rate limiter de 2000 requests/5min por IP

O ALB fica nas public subnets, é o único ponto de entrada da internet. Termina TLS com certificados do ACM o tráfego entre o ALB e os pods pode ser HTTP dentro da VPC, ou HTTPS se quisermos end-to-end encryption.

## Observabilidade

O Nagios actual monitoriza CPU, memória, disco e load. Com a stack que montei, cobrimos isso e muito mais:

| Nagios | Novo equivalente |
|--------|-----------------|
| CPU/Memory por servidor | Métricas por container via Prometheus |
| Disk space | PVC monitoring + node_exporter |
| Load average | kube-state-metrics (pod scheduling, pending, etc.) |
| Alertas por email | Alertmanager → Slack/PagerDuty |
| Dashboard web | Grafana com dashboards pré-configurados |

O Prometheus faz scraping de métricas a cada 15 segundos. O Grafana vem com 3 dashboards da comunidade pré-carregados (cluster overview, node exporter, pods).

## Diferenças entre ambientes

Mantive a mesma arquitectura nos 3 ambientes mas com recursos ajustados:

| | Dev | Staging | Prod |
|---|-----|---------|------|
| NAT Gateway | 1 (single AZ) | 1 | 2 (multi-AZ) |
| EKS nodes | 1-2x t3.micro | 2-4x t3.large | 2-6x t3.large |
| Node type | spot | spot | on-demand |
| RDS | db.t3.micro, single-AZ | db.t3.large, multi-AZ | db.r6g.large, multi-AZ |
| Backups | 7 dias | 14 dias | 35 dias |
| Deletion protection | não | não | sim |
| Monitoring storage | sem PVC | com PVC | com PVC |

Isto permite testar a arquitectura completa em dev sem gastar muito, e ter confiança de que o que funciona em staging vai funcionar em prod.
