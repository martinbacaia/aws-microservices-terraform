provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "aws-microservices-terraform"
      ManagedBy   = "terraform"
      Component   = "tf-backend-bootstrap"
      Environment = "shared"
    }
  }
}
