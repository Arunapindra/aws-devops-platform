terraform {
  backend "s3" {
    bucket         = "aws-devops-platform-terraform-state"
    key            = "environments/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "aws-devops-platform-terraform-locks"
  }
}
