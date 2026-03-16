module "vpc" {
  source             = "../../VPC"
  project_name       = var.project_name
  environment        = "prod"
  single_nat_gateway = false # Multi-AZ: um NAT por AZ para redundância
}

module "ecr" {
  source           = "../../ECR"
  project_name     = var.project_name
  environment      = "prod"
  repository_names = ["stopwatch-app"]
}

module "eks" {
  source              = "../../EKS"
  project_name        = var.project_name
  environment         = "prod"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  kubernetes_version  = "1.32"
  node_instance_types = ["t3.large"]
  node_min_size       = 2
  node_max_size       = 6
  node_desired_size   = 3
  # capacity_type = "ON_DEMAND" - definido no módulo quando env == "prod"
}

module "alb" {
  source            = "../../ALB"
  project_name      = var.project_name
  environment       = "prod"
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}

module "rds" {
  source                     = "../../RDS"
  project_name               = var.project_name
  environment                = "prod"
  vpc_id                     = module.vpc.vpc_id
  data_subnet_ids            = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.node_security_group_id]
  instance_class             = "db.r6g.large"
  allocated_storage          = 100
  multi_az                   = true
  backup_retention_period    = 35
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