# eks-cluster
EKS control plane: cluster, KMS key for secrets encryption, CloudWatch log group, cluster IAM role,
Access Entries (admins get cluster-admin, teams get a Kubernetes group).
Refuses to open the API publicly without an explicit CIDR list.
Key inputs: cluster_name, kubernetes_version, subnet_ids, admin_role_arns, team_access.
Key outputs: cluster_name, cluster_endpoint, cluster_ca_data, kms_key_arn.
