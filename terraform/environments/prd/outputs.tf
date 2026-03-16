output "vpc_id"             { value = module.vpc.vpc_id }
output "eks_cluster_name"   { value = module.eks.cluster_name }
output "eks_endpoint"       { value = module.eks.cluster_endpoint; sensitive = true }
output "alb_dns_name"       { value = module.alb.alb_dns_name }
output "ecr_repository_urls" { value = module.ecr.repository_urls }
output "rds_endpoint"       { value = module.rds.rds_endpoint; sensitive = true }