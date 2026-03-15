# aws-eks-balance-service-demo

Demostración de arquitectura cloud-native en AWS con dos microservicios Python que se comunican via gRPC, desplegados en un cluster EKS usando módulos reutilizables de Terraform.

## Descripción

Este proyecto implementa un servicio de consulta de saldos bancarios como caso de uso para demostrar patrones modernos de infraestructura en AWS:

- Dos microservicios Python que se comunican via **gRPC**
- Infraestructura como código con **módulos reutilizables de Terraform**
- Despliegue en **Amazon EKS** expuesto via **Application Load Balancer**
- Pipeline de **CI/CD con AWS CodeBuild**
- Imágenes almacenadas en **Amazon ECR**
- Estado remoto de Terraform en **S3 + DynamoDB**

> Nota: próposito de este proyecto no es demostrar como funciona el codigo de los dos servicios en python, considerar que estos servicios son solo con fines educativos, por esta razón son extremadamente simples sin considerar las mejores prácticas de cualquier aplicación del mundo real.

---

## Arquitectura

```
Internet
    │
    ▼
[ ALB - Application Load Balancer ]        ← Subnet Pública (us-east-1a / us-east-1b)
    │
    ▼
[ balance-gateway ] (FastAPI :8000)        ← Subnet Privada
    │  HTTP → gRPC
    ▼
[ balance-service ] (gRPC :50051)          ← Subnet Privada
```

### Componentes

| Componente      | Tecnología       | Descripción                          |
| --------------- | ---------------- | ------------------------------------ |
| balance-gateway | Python / FastAPI | API REST que traduce HTTP a gRPC     |
| balance-service | Python / gRPC    | Servidor gRPC con lógica de negocio  |
| Networking      | Terraform Module | VPC, subnets, NAT Gateway, IGW       |
| EKS             | Terraform Module | Cluster Kubernetes, node group, IRSA |
| CI/CD           | AWS CodeBuild    | Build, push a ECR y deploy a EKS     |
| Registro        | Amazon ECR       | Almacenamiento de imágenes Docker    |

### Diagrama de Red

```
VPC: 10.0.0.0/16
├── Subnet Pública us-east-1a  (10.0.1.0/24)  → ALB, NAT Gateway
├── Subnet Pública us-east-1b  (10.0.2.0/24)  → ALB
├── Subnet Privada us-east-1a  (10.0.10.0/24) → EKS Nodes
└── Subnet Privada us-east-1b  (10.0.11.0/24) → EKS Nodes
```

Los nodos EKS viven en subnets privadas y acceden a internet via NAT Gateway. El ALB vive en las subnets públicas y enruta tráfico hacia los pods.

---

## Estructura del Repositorio

```
aws-eks-balance-service-demo/
├── apps/
│   ├── balance-gateway/          # FastAPI HTTP → gRPC gateway
│   │   ├── app/
│   │   ├── Dockerfile
│   │   └── pyproject.toml
│   └── balance-service/          # gRPC server
│       ├── app/
│       ├── Dockerfile
│       └── pyproject.toml
├── proto/
│   ├── balance.proto             # Contrato gRPC
│   └── generated/                # Stubs generados por protoc
├── terraform/
│   ├── modules/
│   │   ├── networking/           # Módulo VPC + subnets
│   │   └── eks/                  # Módulo EKS + ECR + CodeBuild
│   └── environments/
│       └── dev/                  # Configuración del entorno dev
├── k8s/                          # Manifiestos de Kubernetes
│   ├── balance-service-deployment.yml
│   ├── balance-service-service.yml
│   ├── balance-gateway-deployment.yml
│   ├── balance-gateway-service.yml
│   └── balance-gateway-ingress.yml
├── .codebuild/
│   └── buildspec.yml             # Pipeline de CI/CD
├── scripts/
│   ├── bootstrap.sh              # Crea S3 + DynamoDB para Terraform state
│   ├── validate_prerequisites.sh # Valida herramientas instaladas
│   ├── generate_proto.sh         # Genera stubs de gRPC
│   ├── k8s_cleanup.sh            # Elimina recursos de Kubernetes
│   └── cleanup.sh                # Elimina recursos de bootstrap
├── docs/
│   └── DEPLOYMENT_GUIDE.md       # Guía completa de despliegue
└── Makefile                      # Automatización de tareas comunes
```

---

## Stack Tecnológico

**Aplicaciones**

- Python 3.11
- FastAPI + Uvicorn
- gRPC / Protocol Buffers
- Poetry (gestión de dependencias)

**Infraestructura**

- Terraform >= 1.5
- AWS EKS (Kubernetes 1.29)
- AWS VPC, ALB, ECR, CodeBuild
- Helm (AWS Load Balancer Controller)

**Contenedores**

- Docker multi-stage builds
- Multi-platform (linux/amd64 + linux/arm64)

---

## Inicio Rápido

### Prerequisitos

Asegúrate de tener instalado: AWS CLI v2, Docker, kubectl, Terraform >= 1.5, Poetry, Python 3.11+, Helm y Git.

Valida todo con un solo comando:

```bash
./scripts/validate_prerequisites.sh
```

### Despliegue en AWS

Para la guía detallada paso a paso con explicaciones, troubleshooting y notas importantes, consulta **[docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md)**.

---

## Uso Local

```bash
# Instalar dependencias
cd apps/balance-service && poetry install
cd ../balance-gateway && poetry install
cd ../..

# Generar stubs de gRPC
make proto

# Ejecutar servicios localmente
make run-service   # Terminal 1 — gRPC :50051
make run-gateway   # Terminal 2 — HTTP :8000

# Probar
curl http://localhost:8000/health
curl http://localhost:8000/balance/ACC-001

# O con Docker
make docker-build && make docker-run
```

### Cuentas de prueba

| Account ID | Owner         | Balance    |
| ---------- | ------------- | ---------- |
| ACC-001    | Alice Johnson | $15,420.50 |
| ACC-002    | Bob Smith     | $8,930.75  |
| ACC-003    | Carol White   | $32,100.00 |

---

## Módulos de Terraform

### Módulo Networking

```hcl
module "networking" {
  source = "./modules/networking"

  project             = "balance"
  environment         = "dev"
  vpc_cidr            = "10.0.0.0/16"
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones  = ["us-east-1a", "us-east-1b"]
}
```

**Recursos creados:** VPC, Internet Gateway, 2 subnets públicas, 2 subnets privadas, NAT Gateway, Elastic IP, route tables.

### Módulo EKS

```hcl
module "eks" {
  source = "./modules/eks"

  project              = "balance"
  environment          = "dev"
  vpc_id               = module.networking.vpc_id
  private_subnet_ids   = module.networking.private_subnet_ids
  public_subnet_ids    = module.networking.public_subnet_ids
  cluster_version      = "1.29"
  node_instance_type   = "t3.medium"
  desired_node_count   = 2
}
```

**Recursos creados:** EKS cluster, node group, IAM roles, OIDC provider, IRSA para ALB Controller, repositorios ECR, proyecto CodeBuild, CloudWatch log group.

---

## Eliminación de los recursos

```bash
# 1. Eliminar recursos de Kubernetes y ALB
./scripts/k8s_cleanup.sh

# 2. Destruir infraestructura
cd terraform/environments/dev && terraform destroy

# 3. Eliminar recursos de bootstrap
cd ../../.. && ./scripts/cleanup.sh
```

---

## Makefile — Comandos disponibles

| Comando             | Descripción                              |
| ------------------- | ---------------------------------------- |
| `make proto`        | Genera stubs de gRPC desde balance.proto |
| `make install`      | Instala dependencias de ambos servicios  |
| `make run-service`  | Ejecuta balance-service localmente       |
| `make run-gateway`  | Ejecuta balance-gateway localmente       |
| `make docker-build` | Construye imágenes Docker                |
| `make docker-run`   | Levanta contenedores en red local        |
| `make docker-stop`  | Detiene los contenedores                 |
| `make docker-push`  | Construye multi-platform y pushea a ECR  |

---

## Licencia

MIT
