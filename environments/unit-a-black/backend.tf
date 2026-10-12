# Where Terraform keeps its state (its memory of what it built).
#
# DEFAULT: local file terraform.tfstate in this folder. Fine for a first test.
# RECOMMENDED for real use: an S3 bucket IN THIS UNIT'S OWN AWS ACCOUNT.
# Create the bucket once (versioning + encryption on), then uncomment:
#
# terraform {
#   backend "s3" {
#     bucket       = "CHANGE-ME-unit-a-terraform-state"
#     key          = "unit-a-black/eks/terraform.tfstate"
#     region       = "CHANGE-ME"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
#
# After editing, run: ./scripts/tf.sh a init
