# La configuración remota del backend de estado requiere
# que el bucket de S3 y la tabla de DynamoDB ya existan antes de ejecutar «terraform init»
# Para ello, primero debes ejecutar:
# ./scripts/bootstrap.sh to create these resources
# NOTA: recuerda que debes cambiar los valores de «bucket» y «dynamodb_table» por los nombres de tus recursos, asi como la región.

terraform {
  backend "s3" {
    bucket         = "jrx-aws-eks-balance-tfstate"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "jrx-aws-eks-balance-tfstate-lock"
    encrypt        = true
  }
}
