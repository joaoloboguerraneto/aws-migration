# Estratégia de Migração

O desafio pede para propor uma estratégia de migração parcial onde o on-premises fica activo com failover na cloud. Aqui vai o que eu faria.

## Fase 1 — Híbrido (semanas 1-2)

A ideia é simples: não mudar nada no on-premises, mas ter a AWS pronta para assumir se algo correr mal.

### O que montar

**VPN** — Um túnel Site-to-Site VPN entre o datacenter e a VPC na AWS.

**DMS** — AWS Database Migration Service configurado para fazer replicação contínua (CDC) do MySQL on-prem para o RDS. O RDS fica como read replica recebe todos os dados mas não serve a aplicação.

**EKS mínimo** — O cluster corre com 1-2 nodes pequenos, só para manter os pods quentes. Não recebem tráfego real.

**Route 53** — Configurar health checks no endpoint on-premises. Se o health check falhar 3 vezes seguidas (30 segundos), o DNS faz failover automático para o ALB na AWS.

### Como funciona o failover

1. Route 53 detecta que o on-prem está em baixo (~30s)
2. DNS TTL expira, tráfego redireccionado para AWS (~60s)
3. RDS replica é promovida a standalone (~60-120s)
4. Pods no EKS já estão a correr, começam a servir
5. Cluster Autoscaler escala nodes conforme a carga (~3-5min)

Downtime total para o utilizador: 2-4 minutos, dependendo do TTL do DNS.

## Fase 2 — Migração completa (semana 3)

Quando o setup híbrido estiver validado (testámos o failover, confirmámos que os dados replicam correctamente), fazemos o cutover.

### Passos durante a janela de manutenção

1. Anunciar manutenção aos utilizadores
2. Parar as escritas no MySQL on-prem (colocar app em modo leitura)
3. Esperar que o DMS sincronize lag de replicação tem de chegar a zero
4. Promover o RDS para instância independente
5. Actualizar o Route 53 para apontar ao ALB como primário
6. Verificar que a aplicação responde correctamente
7. Abrir escritas

O tempo total é cerca de 10 minutos. O on-prem fica como rollback durante 48 horas se algo estiver errado, voltamos com uma mudança de DNS.

### Rollback

Se correr mal:
- Route 53 volta a apontar para on-prem (~60s com TTL baixo)
- MySQL on-prem pode ser re-sincronizado com mysqldump do RDS
- A decisão de rollback tem de ser tomada nas primeiras 48h, antes dos dados divergirem demasiado

## Fase 3 — Optimização (semanas 4-6)

Com tudo na AWS e estável:

- Activar CloudFront para caching de assets estáticos na edge
- Configurar auto-scaling policies baseadas nos padrões reais de tráfego
- Montar cross-region replication do RDS para DR a sério (noutra região)
- Comprar Reserved Instances para os nodes de prod (poupança de ~40%)
- Implementar blue/green ou canary deploys
- Após 2 semanas sem incidentes, descomissionar o datacenter

## Diagrama do setup híbrido

```
                    Route 53 (failover routing)
                   /                            \
              Primary                        Secondary
           (on-prem)                          (AWS)
               |                                |
          Firewall/LB                          ALB
            |     |                          |     |
         Web01  Web02                     Pod-a  Pod-b
               |                                |
            MySQL ──── DMS (CDC) ────→ RDS (read replica)
```

Quando o Route 53 detecta falha no on-prem, o tráfego passa automaticamente para o lado direito do diagrama.