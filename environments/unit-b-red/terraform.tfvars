# Unit B / Red  ->  AWS Account B
# Replace every CHANGE-ME, then save.

cluster_name = "ex-b-eks"
region       = "CHANGE-ME" # e.g. "eu-west-1". Check m7i.2xlarge is offered there.

vpc_id = "vpc-CHANGE-ME"
private_subnet_ids = [
  "subnet-CHANGE-ME-1", # at least 2, in different Availability Zones
  "subnet-CHANGE-ME-2",
]

# Check what is available first (see README, step 5).
kubernetes_version = "1.35"

# Private API endpoint. Terraform must then run from INSIDE the VPC (README step 4).
endpoint_public_access = false

# IAM roles of the platform admins (get cluster-admin).
admin_role_arns = [
  # "arn:aws:iam::222222222222:role/platform-admin",
]

# Team access, limited to their own namespaces. A namespace used here must also exist in
# 'namespaces' (add it in variables.tf defaults or here). Leave empty to start.
team_access = {
  # data = {
  #   principal_arn = "arn:aws:iam::222222222222:role/team-data"
  #   namespaces    = ["ex-app-data"]
  # }
}

tags = {
  Unit    = "B"
  Network = "Red"
}
