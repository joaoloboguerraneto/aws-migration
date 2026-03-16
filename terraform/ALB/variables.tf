variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "domain_name" {
  description = "Domain name for ACM certificate (e.g., app.example.com)"
  type        = string
  default     = ""
}