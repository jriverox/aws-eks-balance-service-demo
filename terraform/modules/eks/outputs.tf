output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  description = "Base64 encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_oidc_issuer" {
  description = "OIDC issuer URL — required for IRSA configuration"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "node_group_role_arn" {
  description = "ARN of the IAM role attached to the node group"
  value       = aws_iam_role.node_group.arn
}

output "ecr_balance_service_url" {
  description = "ECR repository URL for balance-service"
  value       = aws_ecr_repository.balance_service.repository_url
}

output "ecr_balance_gateway_url" {
  description = "ECR repository URL for balance-gateway"
  value       = aws_ecr_repository.balance_gateway.repository_url
}

output "alb_controller_role_arn" {
  description = "ARN of the IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}