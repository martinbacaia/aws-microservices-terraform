# Remote state — values come from `bootstrap/`. The bucket and table must
# exist before `terraform init` works here.
#
# Override at init time if you cloned the repo and brought your own backend:
#   terraform init \
#     -backend-config="bucket=<your-state-bucket>" \
#     -backend-config="kms_key_id=alias/<your-state-bucket>"

terraform {
  backend "s3" {
    bucket         = "tfstate-aws-microservices-CHANGE-ME"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
    kms_key_id     = "alias/tfstate-aws-microservices-CHANGE-ME"
  }
}
