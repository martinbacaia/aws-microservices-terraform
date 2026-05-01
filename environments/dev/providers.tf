provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "aws-microservices-terraform"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}
