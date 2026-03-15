# Deployment Guide — AWS EKS Balance Service

Guía completa paso a paso para desplegar un cluster de Kubernetes en AWS usando Terraform, con dos microservicios que se comunican via gRPC.

## Tabla de Contenidos

1. [Arquitectura](#arquitectura)
2. [Prerequisitos](#prerequisitos)
3. [Ejecución Local](#ejecución-local)
4. [Bootstrap — Recursos Base en AWS](#bootstrap)
5. [Infraestructura con Terraform](#infraestructura-con-terraform)
6. [Gestión del Cluster EKS](#gestión-del-cluster-eks)
7. [Construir y Pushear Imágenes a ECR](#construir-y-pushear-imágenes-a-ecr)
8. [Despliegue en Kubernetes](#despliegue-en-kubernetes)
9. [Validación](#validación)
10. [Teardown — Eliminación de Recursos](#teardown)
11. [Troubleshooting](#troubleshooting)

---

## Arquitectura

```
Internet
    │
    ▼
[ ALB - Application Load Balancer ]   ← Subnet Pública
    │
    ▼
[ balance-gateway ] (FastAPI :8000)   ← Subnet Privada
    │  HTTP → gRPC
    ▼
[ balance-service ] (gRPC :50051)     ← Subnet Privada
```

La arquitectura despliega dos microservicios en un cluster EKS dentro de una VPC con subnets públicas y privadas distribuidas en dos availability zones (us-east-1a y us-east-1b).

- **balance-gateway**: API REST en FastAPI que traduce llamadas HTTP a gRPC
- **balance-service**: Servidor gRPC que responde consultas de saldo de cuentas

El tráfico externo entra por el ALB en las subnets públicas y es enrutado al gateway en las subnets privadas. La comunicación entre gateway y service ocurre dentro del cluster via DNS interno de Kubernetes.

---

## Prerequisitos

### Herramientas requeridas

| Herramienta | Versión mínima | Instalación                                                       |
| ----------- | -------------- | ----------------------------------------------------------------- |
| AWS CLI     | v2             | [aws.amazon.com/cli](https://aws.amazon.com/cli/)                 |
| Docker      | 20+            | [docs.docker.com](https://docs.docker.com/get-docker/)            |
| kubectl     | v1.29+         | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/)          |
| Terraform   | v1.5+          | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| Poetry      | v1.8+          | [python-poetry.org](https://python-poetry.org/docs/)              |
| Python      | 3.11+          | [python.org](https://www.python.org/downloads/)                   |
| Helm        | v3+            | [helm.sh](https://helm.sh/docs/intro/install/)                    |
| Git         | cualquier      | [git-scm.com](https://git-scm.com/)                               |

### Configuración de AWS

Configura tus credenciales de AWS antes de continuar:

```bash
aws configure
```

La cuenta de AWS debe tener permisos para crear: VPC, EKS, EC2, IAM, ECR, S3, DynamoDB, CodeBuild y CloudWatch.

### Validar prerequisitos

El repositorio incluye un script que valida automáticamente que todo esté instalado y configurado:

```bash
# Otorgar permisos de ejecución a todos los scripts
chmod +x scripts/validate_prerequisites.sh
chmod +x scripts/bootstrap.sh
chmod +x scripts/k8s_cleanup.sh
chmod +x scripts/cleanup.sh
chmod +x scripts/generate_proto.sh

# Ejecutar validación
./scripts/validate_prerequisites.sh
```

Deberías ver todos los checks en verde con `[OK]`. Si alguno falla, instala la herramienta indicada antes de continuar.

---

## Ejecución Local

Esta sección es opcional pero recomendada para entender los servicios antes de desplegarlos en AWS.

### Instalar dependencias

```bash
# balance-service
cd apps/balance-service
poetry install

# balance-gateway
cd ../balance-gateway
poetry install
cd ../..
```

### Generar stubs de gRPC

Los stubs son el código Python generado a partir del contrato `.proto`. Son necesarios para que ambos servicios puedan comunicarse:

```bash
make proto
```

Este comando compila `proto/balance.proto` y genera los archivos `balance_pb2.py` y `balance_pb2_grpc.py` en `proto/generated/`.

### Ejecutar localmente

Abre dos terminales desde la raíz del repo:

```bash
# Terminal 1 — arranca balance-service (gRPC en :50051)
make run-service

# Terminal 2 — arranca balance-gateway (HTTP en :8000)
make run-gateway
```

Prueba el flujo completo HTTP → gRPC → respuesta JSON:

```bash
curl http://localhost:8000/balance/ACC-001
curl http://localhost:8000/balance/ACC-999   # cuenta inexistente → 404
curl http://localhost:8000/health
```

### Ejecutar con Docker

```bash
make docker-build   # construye las imágenes
make docker-run     # levanta los contenedores en red local
```

Para detener:

```bash
make docker-stop
```

---

## Bootstrap

Terraform necesita un bucket S3 para almacenar su estado remoto y una tabla DynamoDB para los locks. Estos recursos deben existir **antes** de ejecutar Terraform.

### Paso 1 — Configurar el script

Edita `scripts/bootstrap.sh` y establece los valores de estas variables:

```bash
AWS_REGION="us-east-1"
S3_BUCKET="<prefijo-unico>-tfstate"
DYNAMODB_TABLE="<prefijo-unico>-tfstate-lock"
```

> **Nota:** Los nombres de buckets S3 son únicos globalmente. Usa un prefijo personal o el ID de tu cuenta para garantizar unicidad. Ejemplo: `jrx-aws-eks-balance-tfstate`.

### Paso 2 — Configurar el backend de Terraform

Edita `terraform/environments/dev/backend.tf` con los mismos valores:

```hcl
terraform {
  backend "s3" {
    bucket         = "<tu-bucket>"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "<tu-tabla-dynamodb>"
    encrypt        = true
  }
}
```

### Paso 3 — Ejecutar bootstrap

```bash
./scripts/bootstrap.sh
```

Output esperado:

```
[INFO]  S3 bucket '<nombre>' created successfully.
[INFO]  DynamoDB table '<nombre>' created successfully.
[INFO]  Region:          us-east-1
[INFO]  Listo, ahora puedes ejecutar: cd terraform/environments/dev && terraform init
```

---

## Infraestructura con Terraform

### Módulos incluidos

**Módulo Networking** (`terraform/modules/networking/`): crea la VPC con subnets públicas y privadas en dos availability zones, Internet Gateway, NAT Gateway y route tables.

**Módulo EKS** (`terraform/modules/eks/`): crea el cluster EKS, node group con instancias t3.medium, roles IAM con IRSA, repositorios ECR y proyecto CodeBuild para CI/CD.

### Paso 1 — Preparar el entorno con Terraform init

```bash
cd terraform/environments/dev
terraform init
```

Output esperado:

```
Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

### Paso 2 — Verificar antes de la creación de recursos con Terraform plan

```bash
terraform plan
```

Revisa los recursos que se van a crear. La línea final debe mostrar:

```
Plan: 35 to add, 0 to change, 0 to destroy.
```

### Paso 3 — Crear los recursos con Terraform apply

```bash
terraform apply
```

Escribe `yes` cuando te lo solicite. Este proceso toma entre **15 y 20 minutos**.

Output esperado:

```
Apply complete! Resources: 35 added, 0 changed, 0 destroyed.
```

### Paso 4 — Obtener los outputs

```bash
terraform output
```

Guarda estos valores para los pasos siguientes:

```
alb_controller_role_arn = "arn:aws:iam::<cuenta>:role/balance-dev-alb-controller-role"
cluster_name            = "balance-dev-cluster"
ecr_balance_gateway_url = "<cuenta>.dkr.ecr.us-east-1.amazonaws.com/balance-dev-balance-gateway"
ecr_balance_service_url = "<cuenta>.dkr.ecr.us-east-1.amazonaws.com/balance-dev-balance-service"
```

---

## Gestión del Cluster EKS

Tal vez te preguntes: ¿Por qué separar la infraestructura (código Terraform) base de la capa de aplicación (gestión de Kubernetes)? La respuesta está relacionada al principio de separación de preocupaciones (SoC).

En resumen,para limitar el alcance de un posible fallo y reducir el riesgo operativo, he desacoplado la infraestructura base (red, VPC) de la capa de aplicación (servicios de Kubernetes).
Esta separación garantiza que cualquier cambio o error en la configuración de las aplicaciones o servicios (como actualizaciones de versiones gRPC o modificaciones en los Services) quede aislado únicamente en ese dominio. De esta forma, se evita que una modificación rutinaria pueda comprometer la infraestructura crítica, previniendo así una caída general del sistema.

**Nota:** Antes de empezar, asegúrate de:

- estar en la ruta raíz del proyecto (terminal).
- algunos de los comando a continuación tienen placeholder que debes reemplazar con tus propios valores, ejemplo: `<cuenta>` se refiere a tu cuenta AWS.

### Paso 1 — Conectar kubectl al cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name balance-dev-cluster
```

> Usa el valor de `cluster_name` del output de Terraform si usaste un nombre diferente.

### Paso 2 — Verificar los nodos

```bash
kubectl get nodes
```

Deberías ver 2 nodos con status `Ready`:

```
NAME                          STATUS   ROLES    AGE   VERSION
ip-10-0-10-xxx.ec2.internal   Ready    <none>   5m    v1.29.x
ip-10-0-11-xxx.ec2.internal   Ready    <none>   5m    v1.29.x
```

### Paso 3 — Agregar repositorio de Helm

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
```

### Paso 4 — Instalar AWS Load Balancer Controller

El AWS Load Balancer Controller crea ALBs en AWS cuando detecta un recurso Ingress en Kubernetes.

```bash
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --version 1.8.1 \
  --set clusterName=balance-dev-cluster \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<alb_controller_role_arn>
```

> **Importante:** Usa la versión `1.8.1` del chart. Versiones 3.x requieren Kubernetes 1.30+ y no son compatibles con este cluster.

### Paso 5 — Verificar el controller

```bash
kubectl get pods -n kube-system | grep aws-load-balancer
```

Deberías ver 2 pods con status `Running`:

```
aws-load-balancer-controller-xxx   1/1   Running   0   2m
aws-load-balancer-controller-xxx   1/1   Running   0   2m
```

---

## Construir y Pushear Imágenes a ECR

### Paso 1 — Autenticarse en ECR

```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <cuenta>.dkr.ecr.us-east-1.amazonaws.com
```

Output esperado: `Login Succeeded`

### Paso 2 — Configurar el Makefile

Edita el `Makefile` en la raíz del repo con los valores de tu cuenta:

```makefile
ECR_REGISTRY = <cuenta>.dkr.ecr.<region>.amazonaws.com
ECR_SERVICE   = balance-dev-balance-service
ECR_GATEWAY   = balance-dev-balance-gateway
```

### Paso 3 — Construir y pushear

Asegúrate de ejecutar los siguientes comandos en la raiz del proyecto.

```bash
make docker-build   # construye imágenes locales
make docker-push    # construye multi-platform y pushea a ECR
```

> **Nota:** `make docker-push` usa `docker buildx --platform linux/amd64,linux/arm64` para generar imágenes compatibles con nodos EC2 AMD64, incluso si tu máquina es ARM (Apple Silicon).

---

## Despliegue en Kubernetes

### Paso 1 — Actualizar las imágenes en los manifiestos

Edita `k8s/balance-service-deployment.yml` y actualiza el campo `image`:

```yaml
image: <cuenta>.dkr.ecr.<region>.amazonaws.com/balance-dev-balance-service:latest
```

Haz lo mismo en `k8s/balance-gateway-deployment.yml`:

```yaml
image: <cuenta>.dkr.ecr.<region>.amazonaws.com/balance-dev-balance-gateway:latest
```

### Paso 2 — Aplicar los manifiestos

```bash
kubectl apply -f k8s/
```

Output esperado:

```
deployment.apps/balance-service created
deployment.apps/balance-gateway created
service/balance-service created
service/balance-gateway created
ingress.networking.k8s.io/balance-gateway-ingress created
```

### Paso 3 — Verificar los pods

```bash
kubectl get pods
```

Espera hasta que todos estén `1/1 Running`:

```
NAME                               READY   STATUS    RESTARTS   AGE
balance-gateway-xxx                1/1     Running   0          2m
balance-gateway-xxx                1/1     Running   0          2m
balance-service-xxx                1/1     Running   0          2m
balance-service-xxx                1/1     Running   0          2m
```

### Paso 4 — Verificar el ALB

```bash
kubectl get ingress
```

El campo `ADDRESS` puede tardar 2-3 minutos en aparecer:

```
NAME                      CLASS   HOSTS   ADDRESS                                     PORTS
balance-gateway-ingress   alb     *       k8s-default-xxx.us-east-1.elb.amazonaws.com  80
```

Copia el valor de `ADDRESS` — es la URL pública de tu aplicación.

---

## CI/CD con CodeBuild

El módulo EKS provisiona automáticamente un pipeline de CI/CD en AWS CodeBuild que se activa con cada `push` a la rama `main`.

### Flujo del pipeline

```text
git push → GitHub Webhook → CodeBuild → docker build → ECR push → kubectl set image → EKS
```

### Paso 1 — Activar la conexión de GitHub (una sola vez)

Terraform crea la conexión con GitHub, pero AWS requiere una autorización manual por seguridad. Después de `terraform apply`:

1. Ve a **AWS Console → Developer Tools → Settings → Connections**
2. Busca la conexión `balance-dev-github` (estado: **Pending**)
3. Haz clic en ella → **"Update pending connection"**
4. Autoriza el acceso a tu cuenta de GitHub en el popup de OAuth

Una vez activada, el webhook queda configurado automáticamente y cualquier `push` a `main` disparará el pipeline.

### Paso 2 — Autorizar CodeBuild en EKS (una sola vez)

CodeBuild necesita permiso para ejecutar `kubectl` dentro del cluster. Después de `terraform apply`, agrega el role al `aws-auth` ConfigMap:

```bash
kubectl patch configmap aws-auth -n kube-system --patch '
{"data":{"mapRoles":"- rolearn: arn:aws:iam::<cuenta>:role/balance-dev-eks-node-role\n  groups:\n  - system:bootstrappers\n  - system:nodes\n  username: system:node:{{EC2PrivateDNSName}}\n- rolearn: arn:aws:iam::<cuenta>:role/balance-dev-codebuild-role\n  groups:\n  - system:masters\n  username: codebuild\n"}}'
```

> Reemplaza `<cuenta>` con tu AWS account ID (ej. `456102076320`).

Verifica que quedó aplicado:

```bash
kubectl get configmap aws-auth -n kube-system -o yaml
```

Debes ver ambos roles: `balance-dev-eks-node-role` y `balance-dev-codebuild-role`.

### Paso 3 — Verificar el pipeline

Después de hacer un `push` a `main`:

```bash
# Ver ejecuciones del pipeline
aws codebuild list-builds-for-project \
  --project-name balance-dev-pipeline \
  --region us-east-1

# Ver logs de la última ejecución
aws codebuild batch-get-builds \
  --ids $(aws codebuild list-builds-for-project \
    --project-name balance-dev-pipeline \
    --query 'ids[0]' --output text) \
  --region us-east-1 \
  --query 'builds[0].{status:buildStatus,phase:currentPhase}'
```

También puedes verlo en **AWS Console → CodeBuild → balance-dev-pipeline**.

### Disparar el pipeline manualmente

Si necesitas hacer un deploy sin hacer push:

```bash
aws codebuild start-build \
  --project-name balance-dev-pipeline \
  --region us-east-1
```

---

## Validación

```bash
# Health check
curl http://<ALB-ADDRESS>/health

# Consulta de saldo — cuenta existente
curl http://<ALB-ADDRESS>/balance/ACC-001

# Consulta de saldo — cuenta inexistente (debe retornar 404)
curl http://<ALB-ADDRESS>/balance/ACC-999
```

Cuentas de prueba disponibles: `ACC-001`, `ACC-002`, `ACC-003`.

---

## Eliminación de recursos (Clean-up)

Sigue este orden estrictamente. Si eliminas EKS antes que los recursos de Kubernetes, el ALB queda huérfano y Terraform no puede eliminar la VPC.

### Paso 1 — Eliminar recursos de Kubernetes

```bash
./scripts/k8s_cleanup.sh
```

Este script elimina los deployments, services e ingress, espera 60 segundos para que el Load Balancer Controller elimine el ALB, y desinstala el controller.

### Paso 2 — Destruir la infraestructura

```bash
cd terraform/environments/dev
terraform destroy
```

Escribe `yes` cuando te lo solicite. Tarda entre 15 y 20 minutos.

### Paso 3 — Eliminar recursos de bootstrap

```bash
cd ../../..
./scripts/cleanup.sh
```

Este script elimina las imágenes de ECR, el bucket S3 y la tabla DynamoDB.

---

## Troubleshooting

### `ImagePullBackOff` en los pods

**Causa:** Imágenes construidas para ARM64 en nodos EC2 AMD64.

**Solución:** Usa `make docker-push` que construye imágenes multi-platform automáticamente.

---

### El Ingress no tiene ADDRESS

**Causa 1:** El controller no está corriendo. Revisa los logs:

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller | tail -20
```

**Causa 2:** Versión del chart incompatible con Kubernetes 1.29.

**Solución:** Reinstala con la versión correcta:

```bash
helm uninstall aws-load-balancer-controller -n kube-system
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --version 1.8.1 ...
```

---

### `AccessDenied: elasticloadbalancing:DescribeListenerAttributes`

**Causa:** Política IAM desactualizada sin los permisos necesarios.

**Solución:**

```bash
curl -o terraform/modules/eks/policies/alb-controller-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.0/docs/install/iam_policy.json

cd terraform/environments/dev
terraform apply -replace="module.eks.aws_iam_policy.alb_controller"
```

---

### `CrashLoopBackOff` en balance-service con liveness/readiness probe timeout

**Causa:** El `timeoutSeconds` de los probes no estaba definido, por lo que Kubernetes usaba el default de 1 segundo. Con grpcio 1.78.x, arrancar el intérprete Python e importar el módulo `grpc` toma más de 1s, haciendo que el probe siempre falle por timeout. Tras 3 fallos consecutivos, Kubernetes mata el pod.

Para confirmar, ejecuta:

```bash
kubectl describe pod -n default <nombre-pod-balance-service>
```

Busca en los eventos:

```text
Liveness probe failed: command timed out
```

**Solución:** El manifiesto `k8s/balance-service-deployment.yml` ya incluye `timeoutSeconds: 10` en ambos probes. Si el cluster ya está desplegado, aplica el cambio directamente:

```bash
kubectl apply -f k8s/balance-service-deployment.yml
```

---

### CodeBuild falla con `toomanyrequests` al hacer `docker build`

**Causa:** Docker Hub aplica rate limiting a pulls anónimos desde IPs compartidas de AWS. CodeBuild usa IPs compartidas, por lo que supera el límite rápidamente.

**Solución:** Los Dockerfiles ya usan el mirror público de ECR en lugar de Docker Hub:

```dockerfile
# Antes (falla en CodeBuild)
FROM python:3.11-slim

# Después (sin rate limits dentro de AWS)
FROM public.ecr.aws/docker/library/python:3.11-slim
```

---

### CodeBuild falla con `Unauthorized` al ejecutar `kubectl`

**Causa:** El role IAM de CodeBuild no está registrado en el `aws-auth` ConfigMap del cluster. EKS requiere que cualquier identidad IAM que ejecute `kubectl` esté explícitamente autorizada.

**Solución:** Agregar el role de CodeBuild al ConfigMap (ver sección [CI/CD con CodeBuild → Paso 2](#paso-2--autorizar-codebuild-en-eks-una-sola-vez)).

---

### `terraform destroy` falla por ECR no vacío

**Causa:** Los repositorios ECR tienen imágenes.

**Solución:** Ejecuta `./scripts/cleanup.sh` que elimina las imágenes antes del destroy, o vacíalos manualmente desde la consola de AWS.
