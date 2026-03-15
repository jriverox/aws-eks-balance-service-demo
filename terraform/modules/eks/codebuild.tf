# =============================================================================
# CodeBuild — CI/CD Pipeline
# Crea imágenes de Docker, las sube a ECR y las implementa en EKS
# =============================================================================

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# Almacena los logs de ejecución de CodeBuild
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aws/codebuild/${local.name_prefix}-pipeline"
  retention_in_days = 7

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# IAM Role — CodeBuild
# Otorga permisos a ECR, EKS, CloudWatch Logs y S3
# -----------------------------------------------------------------------------
resource "aws_iam_role" "codebuild" {
  name = "${local.name_prefix}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${local.name_prefix}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = [
          aws_ecr_repository.balance_service.arn,
          aws_ecr_repository.balance_gateway.arn
        ]
      },
      {
        Sid    = "EKSDeploy"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = aws_eks_cluster.main.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.codebuild.arn}:*"
      },
      {
        Sid    = "S3Cache"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "arn:aws:s3:::${var.project}-${var.environment}-codebuild-cache/*"
      },
      {
        Sid    = "CodeStarConnection"
        Effect = "Allow"
        Action = ["codestar-connections:UseConnection"]
        Resource = aws_codestarconnections_connection.github.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CodeStar Connection — GitHub
# Permite a CodeBuild acceder al repositorio de GitHub.
# IMPORTANTE: Después de `terraform apply`, la conexión queda en estado PENDING.
# Debes activarla manualmente en:
# AWS Console → Developer Tools → Settings → Connections → clic en la conexión → "Update pending connection"
# -----------------------------------------------------------------------------
resource "aws_codestarconnections_connection" "github" {
  name          = "${local.name_prefix}-github"
  provider_type = "GitHub"

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# CodeBuild Project
# -----------------------------------------------------------------------------
resource "aws_codebuild_project" "main" {
  name          = "${local.name_prefix}-pipeline"
  description   = "CI/CD pipeline for balance-gateway and balance-service"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true # Required for Docker builds

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "ECR_BALANCE_SERVICE_URL"
      value = aws_ecr_repository.balance_service.repository_url
    }

    environment_variable {
      name  = "ECR_BALANCE_GATEWAY_URL"
      value = aws_ecr_repository.balance_gateway.repository_url
    }

    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = aws_eks_cluster.main.name
    }
  }

  source {
    type            = "GITHUB"
    location        = var.github_repo_url
    git_clone_depth = 1
    buildspec       = ".codebuild/buildspec.yml"
  }

  source_version = "main"

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
      status     = "ENABLED"
    }
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# CodeBuild Webhook — Trigger automático en push a main
# Requiere que la conexión GitHub (aws_codestarconnections_connection.github)
# esté en estado Available. Activar en:
# AWS Console → CodePipeline → Settings → Connections → balance-dev-github → Update pending connection
# Una vez activada, descomentar este recurso y correr terraform apply.
# -----------------------------------------------------------------------------
# resource "aws_codebuild_webhook" "main" {
#   project_name = aws_codebuild_project.main.name
#   build_type   = "BUILD"
#
#   filter_group {
#     filter {
#       type    = "EVENT"
#       pattern = "PUSH"
#     }
#
#     filter {
#       type    = "HEAD_REF"
#       pattern = "^refs/heads/main$"
#     }
#   }
# }
