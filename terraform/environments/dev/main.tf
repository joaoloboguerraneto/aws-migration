# ─────────────────────────────────────────────────────────────────────────────
# Environment: DEV
# ─────────────────────────────────────────────────────────────────────────────
# Otimizado para custo: single NAT, spot, RDS sem Multi-AZ, backups 7d
# ─────────────────────────────────────────────────────────────────────────────



module "vpc" {
  source             = "../../VPC"
  project_name       = var.project_name
  environment        = "dev"
  single_nat_gateway = true # custo: ~$32/mês vs $64 com 2
}

module "ecr" {
  source           = "../../ECR"
  project_name     = var.project_name
  environment      = "dev"
  repository_names = ["stopwatch-app"]
}

module "eks" {
  source              = "../../EKS"
  project_name        = var.project_name
  environment         = "dev"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = ["t3.medium"]
  node_min_size       = 1
  node_max_size       = 3
  node_desired_size   = 2
  # capacity_type = "SPOT" — definido no módulo quando env != "prod"
}

module "alb" {
  source            = "../../ALB"
  project_name      = var.project_name
  environment       = "dev"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}

module "rds" {
  source                     = "../../RDS"
  project_name               = var.project_name
  environment                = "dev"
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
  instance_class             = "db.t3.medium"
  allocated_storage          = 20
  multi_az                   = false
  backup_retention_period    = 7
}

module "monitoring" {
  source                     = "../../monitoring/k8s-monitoring"
  project_name               = var.project_name
  environment                = "dev"
  eks_cluster_name           = module.eks.cluster_name
  eks_cluster_endpoint       = module.eks.cluster_endpoint
  eks_cluster_ca_certificate = module.eks.cluster_ca_certificate
  depends_on                 = [module.eks]
}