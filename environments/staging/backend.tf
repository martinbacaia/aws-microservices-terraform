terraform {
  backend "s3" {
    bucket         = "tfstate-aws-microservices-CHANGE-ME"
    key            = "envs/staging/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
    kms_key_id     = "alias/tfstate-aws-microservices-CHANGE-ME"
  }
}
