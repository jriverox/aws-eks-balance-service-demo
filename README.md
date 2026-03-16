# AWS EKS Balance Service Demo

Este repositorio implementa una arquitectura cloud-native de referencia en Amazon EKS, orquestada íntegramente mediante Terraform. El proyecto se centra en demostrar principios avanzados de **\*_Infraestructura como Código (IaC)_** y **_CI/CD_** automatizado con AWS CodeBuild. Aunque incluye dos microservicios funcionales en Python (FastAPI + gRPC), estos sirven como vehículos educativos para validar el flujo de tráfico North-South (vía ALB) y la comunicación interna East-West (vía gRPC) dentro de una VPC segmentada.

---

## 🛠️ Stack Tecnológico

- **Lenguajes:** Python 3.11 (FastAPI para Gateway, gRPC para Service).
- **Infraestructura:** Terraform (Módulos reutilizables y estado remoto en S3/DynamoDB).
- **Orquestación:** Amazon EKS (Kubernetes 1.29+).
- **Networking:** AWS VPC (Multi-AZ), Application Load Balancer (ALB).
- **CI/CD:** AWS CodeBuild & Amazon ECR.
- **Automatización:** Bash Scripting para validación y despliegue.

---

## 🚀 Inicio Rápido (Operación)

Para un despliegue detallado paso a paso, consulte la [**Guía de Despliegue (DEPLOYMENT_GUIDE.md)**](./DEPLOYMENT_GUIDE.md).

### 1. Validar Entorno Local

Asegúrese de cumplir con los pre-requisitos antes de iniciar:

```bash
./scripts/validate_prerequisites.sh
```

### 2. Bootstrap de Estado Remoto:

```bash
./scripts/bootstrap.sh
```

### 3. Desplegar con Terraform:

```bash
cd terraform/environments/dev
terraform init && terraform apply
```

### 4. Pruebas de Humo

```bash
curl http://<ALB_URL>/balance/ACC-001
```

---

## 📂 Estructura del Proyecto

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

## 🌐 Arquitectura de Red y Flujo de Tráfico

La red se ha diseñado siguiendo el principio de Defensa en Profundidad, segmentando el tráfico en capas lógicas para minimizar la superficie de ataque.

### 1. Segmentación de Red (Justificación)

- Subredes Públicas: Alojan exclusivamente el ALB y el NAT Gateway. Actúan como la zona de amortiguación perimetral.

- Subredes Privadas: Alojan los nodos de cómputo de EKS y las aplicaciones. Esto garantiza que el backend sea invisible desde Internet, cumpliendo con los estándares de seguridad para servicios financieros.

### 2. Flujo de Tráfico y Comunicación gRPC

La arquitectura distingue claramente entre dos tipos de flujos:

- Flujo North-South (Ingreso): El tráfico externo llega al ALB (Subred Pública). Este realiza la terminación TLS/SSL y redirige la petición vía HTTP/1.1 al balance-gateway en la subred privada.

- Flujo East-West (Comunicación Interna gRPC): El balance-gateway traduce la solicitud y se comunica con el balance-service mediante gRPC sobre HTTP/2.
  - Justificación: Esta comunicación ocurre estrictamente dentro del clúster (ClusterIP). Al usar gRPC interno, se reduce la latencia, se mejora el rendimiento mediante la multiplexación de HTTP/2 y se asegura que los datos críticos de balance nunca abandonen la red privada.

### 🔒 Seguridad y Resiliencia

Multi-AZ: Despliegue en us-east-1a y us-east-1b para tolerancia a fallos.

Salida Controlada: Los nodos acceden a servicios como ECR para pull de imágenes únicamente a través de NAT Gateways.

Security Groups: Implementados como firewalls a nivel de instancia, permitiendo solo el tráfico necesario (Puerto 8000 para el Gateway y 50051 para el Service).

---

## ⚙️ Automatización (Scripts)

- ./scripts/validate_prerequisites.sh: Verifica versiones de Terraform, AWS CLI, Docker, etc.

- ./scripts/bootstrap.sh: Configura el S3 y DynamoDB para el estado remoto.

- ./scripts/generate_proto.sh: Automatiza la generación de stubs de Python para gRPC.

- ./scripts/k8s_cleanup.sh: Asegura el borrado de recursos de K8s para una destrucción limpia de la infra.

---
