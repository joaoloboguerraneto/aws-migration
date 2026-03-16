variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "aws-migration"
}

variable "github_org" {
  description = "GitHub username ou organization (ex: joao-github)"
  type        = string
  default     = "joaoloboguerraneto"
}

variable "github_repo" {
  description = "Nome do repositório GitHub"
  type        = string
  default     = "aws-migration"
}

variable "environments" {
  description = "GitHub Environments permitidos"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}