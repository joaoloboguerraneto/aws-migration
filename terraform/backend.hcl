# ─────────────────────────────────────────────────────────────────────────────
# Terraform Backend - Configuração Parcial
# ─────────────────────────────────────────────────────────────────────────────
#
# Este ficheiro é usado por TODOS os environments.
# O campo "key" é definido no backend block de cada environment.
#
# Uso:
#   cd terraform/environments/dev
#   terraform init -backend-config=../../backend.hcl
#
# State paths resultantes:
#   s3://<bucket>/dev/terraform.tfstate
#   s3://<bucket>/staging/terraform.tfstate
#   s3://<bucket>/prod/terraform.tfstate
#
# Criado pelo módulo terraform/S3 (bootstrap)
# ─────────────────────────────────────────────────────────────────────────────

bucket         = "neto-challenge-032026"
region         = "us-east-1"
dynamodb_table = "neto-challenge-terraform-locks"
encrypt        = true
