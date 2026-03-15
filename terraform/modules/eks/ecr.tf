# =============================================================================
# ECR Repositories
# Una por servicio: almacena imágenes de Docker creadas por CodeBuild
# =============================================================================

resource "aws_ecr_repository" "balance_service" {
  name                 = "${local.name_prefix}-balance-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-balance-service"
  })
}

resource "aws_ecr_repository" "balance_gateway" {
  name                 = "${local.name_prefix}-balance-gateway"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-balance-gateway"
  })
}

# -----------------------------------------------------------------------------
# ECR Lifecycle Policies
# Conserva solo las últimas 10 imágenes por repositorio para controlar los costes de almacenamiento
# -----------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "balance_service" {
  repository = aws_ecr_repository.balance_service.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "balance_gateway" {
  repository = aws_ecr_repository.balance_gateway.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
