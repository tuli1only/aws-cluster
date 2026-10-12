###############################################################################
# Reference EKS cluster. Order of creation (arrows = "must exist first"):
#
#   cluster -> core_addons -> general_node_group -> node_addons
#                                                     |-> lb_controller
#                                                     |-> governance
###############################################################################

module "cluster" {
  source = "../../modules/eks-cluster"

  cluster_name            = var.cluster_name
  kubernetes_version      = var.kubernetes_version
  subnet_ids              = var.private_subnet_ids
  endpoint_public_access  = var.endpoint_public_access
  public_access_cidrs     = var.public_access_cidrs
  control_plane_log_types = var.control_plane_log_types
  log_retention_days      = var.log_retention_days
  admin_role_arns         = var.admin_role_arns
  team_access             = var.team_access
}

# VPC CNI, kube-proxy, Pod Identity Agent: needed before nodes can join.
module "core_addons" {
  source = "../../modules/eks-core-addons"

  cluster_name = module.cluster.cluster_name
}

# General / Platform managed node group: 3 x m7i.2xlarge.
module "general_node_group" {
  source = "../../modules/eks-node-group"

  cluster_name    = module.cluster.cluster_name
  node_group_name = "general-platform"
  subnet_ids      = var.private_subnet_ids

  instance_types = var.general_node_group.instance_types
  desired_size   = var.general_node_group.desired_size
  min_size       = var.general_node_group.min_size
  max_size       = var.general_node_group.max_size
  disk_size_gb   = var.general_node_group.disk_size_gb

  labels = {
    "node-group" = "general-platform"
    "workload"   = "platform-delivery"
  }

  depends_on = [module.core_addons]
}

# CoreDNS, EBS CSI driver and StorageClass: need running nodes.
module "node_addons" {
  source = "../../modules/eks-node-addons"

  cluster_name = module.cluster.cluster_name
  kms_key_arn  = module.cluster.kms_key_arn

  depends_on = [module.general_node_group]
}

module "lb_controller" {
  source = "../../modules/eks-lb-controller"

  cluster_name  = module.cluster.cluster_name
  region        = var.region
  vpc_id        = var.vpc_id
  chart_version = var.lbc_chart_version

  depends_on = [module.node_addons]
}

# Namespaces, Pod Security, quotas, NetworkPolicy, RBAC.
module "governance" {
  source = "../../modules/eks-governance"

  namespaces  = var.namespaces
  team_access = var.team_access

  depends_on = [module.node_addons]
}
