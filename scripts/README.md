# scripts/

Automation scripts for environment setup, validation, and resource management.

## Scripts

| Script                      | Description                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| `bootstrap.sh`              | Creates S3 bucket and DynamoDB table for Terraform remote state                          |
| `validate_prerequisites.sh` | Validates all required tools are installed (AWS CLI, Docker, kubectl, Terraform, Poetry) |
| `teardown.sh`               | Destroys S3 bucket and DynamoDB table after terraform destroy                            |
| `generate_proto.sh`         | Regenerates Python gRPC stubs from proto files                                           |

Observación: Asegúrate de que k8s_cleanup.sh se ejecute antes que el terraform destroy principal. Esto es porque si eliminas la VPC antes de que Kubernetes libere el Application Load Balancer, el proceso se quedará "colgado" intentando eliminar una subred que todavía tiene un recurso activo.
