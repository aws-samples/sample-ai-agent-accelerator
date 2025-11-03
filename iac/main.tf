provider "aws" {
  region = var.region
}

# Docker provider with ECR authentication
provider "docker" {
  registry_auth {
    address  = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
    username = "AWS"
    password = data.aws_ecr_authorization_token.token.password
  }
}

# ECR authorization token for Docker provider
data "aws_ecr_authorization_token" "token" {}
