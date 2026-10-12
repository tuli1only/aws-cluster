# Unit A / Black  ->  AWS Account A
# Fill in every value marked CHANGE-ME, then save.

cluster_name = "ex-a-eks"
region       = "CHANGE-ME"            # e.g. "eu-west-1". Check m7i.2xlarge is offered there.

vpc_id = "vpc-CHANGE-ME"
private_subnet_ids = [
  "subnet-CHANGE-ME-1",               # at least 2, in different Availability Zones
  "subnet-CHANGE-ME-2",
]

# Kubernetes version. Check what is available first (see README, step 5).
kubernetes_version = "1.35"

# Private API endpoint (recommended for the Black network).
# Terraform must then run from INSIDE the VPC (see README, "Where to run this").
endpoint_public_access = false

# IAM roles of the platform admins (get cluster-admin).
admin_role_arns = [
  # "arn:aws:iam::111111111111:role/platform-admin",
]

# Team access, limited to their own namespaces. Leave empty {} to start.
team_access = {
  # data = {
  #   principal_arn = "arn:aws:iam::111111111111:role/team-data"
  #   namespaces    = ["ex-app-data"]
  # }
}

tags = {
  Unit    = "A"
  Network = "Black"
}
