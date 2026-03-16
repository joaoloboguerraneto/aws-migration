# Migration Strategy

## Phase 1 — Hybrid (Cloud Failover)

This phase keeps the on-premises infrastructure as **primary** while building a **warm standby** in AWS for disaster recovery.

```
                  Route 53 (Failover Routing)
                 /                            \
            Primary                        Secondary
         (On-Prem)                          (AWS)
             │                                │
        Firewall/LB                          ALB
          │     │                          │     │
       Web01  Web02                     Pod-a  Pod-b
             │                                │
          MySQL ──── DMS CDC ────────→ RDS (Read Replica)
```

### Components

1. **AWS Site-to-Site VPN**: Encrypted tunnel between on-prem and AWS VPC over the internet. For lower latency, upgrade to AWS Direct Connect later.

2. **Route 53 Health Checks**: Monitor the on-prem endpoint (HTTP health check on the firewall's public IP). If the health check fails 3 consecutive times (30 seconds), DNS failover triggers automatically.

3. **AWS DMS (Database Migration Service)**: Continuous replication from on-prem MySQL to RDS MySQL via Change Data Capture (CDC). The RDS instance runs as a read replica during normal operations.

4. **Warm Standby in AWS**: EKS cluster running with **minimum capacity** (1 node per AZ). On failover:
   - Route 53 redirects traffic to the ALB
   - RDS read replica is promoted to primary (automatic with Multi-AZ)
   - Cluster Autoscaler scales up to meet demand

### Failover Sequence

| Step | Action | Time |
|------|--------|------|
| 1 | Route 53 detects on-prem failure | ~30s |
| 2 | DNS TTL expires, traffic shifts to AWS | ~60s |
| 3 | RDS replica promoted to standalone | ~60-120s |
| 4 | EKS pods begin serving traffic | Immediate |
| 5 | Cluster Autoscaler adds capacity | ~3-5min |

**Total failover time: ~2-4 minutes** (depending on DNS TTL)

### Cost (Hybrid Phase)
- VPN: ~$36/month per tunnel
- RDS standby (db.t3.medium): ~$50/month
- EKS control plane: ~$73/month
- Minimum nodes (2× t3.medium spot): ~$30/month
- **Estimated total: ~$200/month** for DR capability

---

## Phase 2 — Full Migration

Once the hybrid setup is validated, the full migration follows:

### Step 1: Pre-Migration (Week 1-2)
- Deploy full Terraform infrastructure to production AWS account
- Configure DMS for full load + CDC
- Validate data consistency with checksums
- Deploy application to EKS, test with synthetic traffic

### Step 2: Migration Window (Planned Downtime)
- Announce maintenance window to users
- Stop writes on on-prem MySQL
- Wait for DMS replication lag to reach zero
- Promote RDS to primary
- Update Route 53 to point to AWS ALB as primary
- Validate application functionality

### Step 3: Post-Migration (Week 3-4)
- Monitor CloudWatch and Grafana dashboards
- Keep on-prem running as fallback (Route 53 secondary)
- After 2 weeks of stable operation, decommission on-prem
- Cancel datacenter lease / repurpose hardware

### Rollback Plan
- Route 53 can switch back to on-prem in ~60 seconds
- On-prem MySQL can be re-synced from RDS via mysqldump
- Rollback decision must be made within the first 48 hours

---

## Phase 3 — Optimization

After full migration:
- Enable CloudFront for edge caching
- Implement auto-scaling policies based on traffic patterns
- Set up cross-region replication for true DR
- Optimize costs with Reserved Instances and Savings Plans
- Implement blue/green or canary deployments