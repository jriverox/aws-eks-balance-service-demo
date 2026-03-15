# ============================================================
# Dev Environment — Module Invocations
# ============================================================
# Este archivo conecta los módulos de networking y eks.
# Las implementaciones de los módulos se encuentran en terraform/modules/

module "networking" {
  source = "../../modules/networking"

  environment = var.environment
  project     = var.project
  aws_region  = var.aws_region

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]
}

module "eks" {
  source = "../../modules/eks"

  environment = var.environment
  project     = var.project
  aws_region  = var.aws_region

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids
}

output "alb_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = module.eks.alb_controller_role_arn
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "ecr_balance_service_url" {
  description = "ECR URL for balance-service"
  value       = module.eks.ecr_balance_service_url
}

output "ecr_balance_gateway_url" {
  description = "ECR URL for balance-gateway"
  value       = module.eks.ecr_balance_gateway_url
}
