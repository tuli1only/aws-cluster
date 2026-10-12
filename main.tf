###############################################################################
# Reference EKS cluster (T06) - deployed independently per unit
#   Unit A / Black  -> AWS Account A -> ex-a-eks
#   Unit B / Red    -> AWS Account B -> ex-b-eks
#
# Scope:
#   1. EKS cluster (AWS-managed control plane)
#   2. General / Platform managed node group: 3 x m7i.2xlarge (8 vCPU / 32 GiB)
#   3. Add-ons: VPC CNI, CoreDNS, kube-proxy, EBS CSI, Pod Identity Agent,
#      AWS Load Balancer Controller
#   4. Governance: RBAC, ResourceQuotas, NetworkPolicy (+ Pod Security labels)
#
# Assumes the VPC and subnets already exist (passed in as variables).
# Run once per account, with a separate tfvars file / state per unit.
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17" # 2.x syntax (kubernetes {} block)
    }
  }

  # backend "s3" {}  # one state per account / unit
}

###############################################################################
# Variables
###############################################################################

variable "region" {
  description = "AWS region. Confirm m7i.2xlarge is offered in it before applying."
  type        = string
}

variable "cluster_name" {
  description = "ex-a-eks for Unit A, ex-b-eks for Unit B"
  type        = string
}

variable "kubernetes_version" {
  description = <<-EOT
    EKS Kubernetes version. Pick one that is in EKS *standard* support, e.g.:
      aws eks describe-cluster-versions --region <region> \
        --query 'clusterVersions[].[clusterVersion,status,endOfStandardSupportDate]' --output table
    1.34 leaves EKS standard support on 2026-12-02, so don't start there.
  EOT
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets (>= 2 AZs) for the control plane ENIs and the nodes. Size them for pod IPs (T09)."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Black/Red networks are private, so the API endpoint is private by default."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  type    = list(string)
  default = []
}

variable "admin_role_arns" {
  description = "IAM roles of platform admins (EKS Access Entries, cluster-admin). Not Keycloak."
  type        = list(string)
  default     = []
}

variable "team_access" {
  description = "Per-team IAM principals, scoped to namespaces. Key = team name."
  type = map(object({
    principal_arn = string
    namespaces    = list(string)
  }))
  default = {}
}

variable "general_node_group" {
  type = object({
    instance_types = list(string)
    desired_size   = number
    min_size       = number
    max_size       = number
    disk_size_gb   = number
  })
  default = {
    instance_types = ["m7i.2xlarge"] # 8 vCPU / 32 GiB
    desired_size   = 3
    min_size       = 3
    max_size       = 3
    disk_size_gb   = 100
  }
}

variable "control_plane_log_types" {
  description = "Selected control plane log categories sent to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "lbc_chart_version" {
  description = "aws-load-balancer-controller Helm chart version. Pin it (null = latest)."
  type        = string
  default     = null
}

variable "namespaces" {
  description = "Governed namespaces: ex-platform-* and ex-app-<team>. Quotas are per namespace."
  type = map(object({
    pod_security_enforce = string # privileged | baseline | restricted
    requests_cpu         = string
    requests_memory      = string
    limits_cpu           = string
    limits_memory        = string
    pods                 = string
    pvcs                 = string
  }))
  default = {
    "ex-platform-ci" = {
      pod_security_enforce = "baseline" # restricted if builds are rootless
      requests_cpu         = "8"
      requests_memory      = "16Gi"
      limits_cpu           = "16"
      limits_memory        = "32Gi"
      pods                 = "50"
      pvcs                 = "0" # stateless runners
    }
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}

###############################################################################
# Providers
###############################################################################

provider "aws" {
  region = var.region

  default_tags {
    tags = merge(var.tags, {
      Cluster   = var.cluster_name
      ManagedBy = "terraform"
    })
  }
}

provider "kubernetes" {
  host                   = aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.this.certificate_authority[0].data)

    exec = [{
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.this.name, "--region", var.region]
    }]
  }
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

###############################################################################
# KMS (secrets envelope encryption) and CloudWatch log group
###############################################################################

resource "aws_kms_key" "eks" {
  description             = "${var.cluster_name} Kubernetes secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "eks" {
  name          = "alias/${var.cluster_name}-secrets"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days
}

###############################################################################
# Cluster IAM role + cluster
###############################################################################

data "aws_iam_policy_document" "eks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.eks_assume.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : null
  }

  # Access Entries only (no aws-auth ConfigMap).
  # bootstrap=true gives the identity running Terraform temporary admin so the
  # kubernetes/helm resources below can be applied. Remove that access entry
  # later if you want Terraform to run through an explicit admin role only.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  enabled_cluster_log_types = var.control_plane_log_types

  # Avoid being silently moved into paid extended support after standard ends.
  upgrade_policy {
    support_type = "STANDARD"
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.eks,
  ]
}

###############################################################################
# Access Entries (platform admins + team-scoped access)
###############################################################################

resource "aws_eks_access_entry" "admin" {
  for_each      = toset(var.admin_role_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = toset(var.admin_role_arns)
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# Teams get no AWS-side policy; authorization is done by RBAC via the group.
resource "aws_eks_access_entry" "team" {
  for_each          = var.team_access
  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  type              = "STANDARD"
  kubernetes_groups = ["ex-team-${each.key}"]
}

###############################################################################
# Node IAM role + General / Platform managed node group
###############################################################################

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    "AmazonEC2ContainerRegistryPullOnly", # image pull from ECR (Q27: image source)
    "AmazonSSMManagedInstanceCore",       # shell access via SSM instead of SSH
  ])
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value}"
}

# The VPC CNI gets its permissions through Pod Identity (below), not the node role.

resource "aws_launch_template" "general" {
  name_prefix = "${var.cluster_name}-general-"

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.general_node_group.disk_size_gb
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # pods can't reach node credentials
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-general"
    }
  }
}

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "general-platform"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = "ON_DEMAND"
  instance_types = var.general_node_group.instance_types

  scaling_config {
    desired_size = var.general_node_group.desired_size
    min_size     = var.general_node_group.min_size
    max_size     = var.general_node_group.max_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.general.id
    version = aws_launch_template.general.latest_version
  }

  labels = {
    "node-group" = "general-platform"
    "workload"   = "platform-delivery"
  }

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
    aws_eks_addon.pod_identity_agent,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

###############################################################################
# Pod Identity helper (trust policy shared by add-on roles)
###############################################################################

data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

###############################################################################
# Add-ons installed before nodes exist: VPC CNI, kube-proxy, Pod Identity Agent
###############################################################################

resource "aws_iam_role" "vpc_cni" {
  name               = "${var.cluster_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.vpc_cni.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Turn on the built-in NetworkPolicy engine so NetworkPolicy is actually enforced (T06).
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  depends_on = [aws_eks_pod_identity_association.vpc_cni]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

###############################################################################
# Add-ons that need nodes: CoreDNS, EBS CSI
###############################################################################

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.general]
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Needed because the StorageClass below encrypts volumes with the cluster KMS key.
data "aws_iam_policy_document" "ebs_csi_kms" {
  statement {
    actions = [
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.eks.arn]
  }
}

resource "aws_iam_role_policy" "ebs_csi_kms" {
  name   = "kms"
  role   = aws_iam_role.ebs_csi.id
  policy = data.aws_iam_policy_document.ebs_csi_kms.json
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.general,
    aws_eks_pod_identity_association.ebs_csi,
  ]
}

# StorageClass: retain, expand, snapshot-friendly, encrypted, zonal-aware.
resource "kubernetes_storage_class_v1" "ebs_gp3" {
  metadata {
    name = "ebs-gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type      = "gp3"
    encrypted = "true"
    kmsKeyId  = aws_kms_key.eks.arn
    fsType    = "ext4"
  }

  depends_on = [aws_eks_addon.ebs_csi]
}

###############################################################################
# AWS Load Balancer Controller (Helm + Pod Identity)
###############################################################################

resource "aws_iam_role" "lbc" {
  name               = "${var.cluster_name}-lbc"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
}

resource "aws_iam_policy" "lbc" {
  name   = "${var.cluster_name}-lbc"
  policy = file("${path.module}/lbc_iam_policy.json") # official upstream policy
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = aws_iam_policy.lbc.arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

resource "helm_release" "lbc" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lbc_chart_version

  values = [yamlencode({
    clusterName  = aws_eks_cluster.this.name
    region       = var.region
    vpcId        = var.vpc_id
    replicaCount = 2
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }
  })]

  depends_on = [
    aws_eks_node_group.general,
    aws_eks_addon.coredns,
    aws_eks_addon.vpc_cni,
    aws_eks_pod_identity_association.lbc,
    aws_iam_role_policy_attachment.lbc,
  ]
}

###############################################################################
# Hierarchical governance: Namespaces, Pod Security, ResourceQuotas,
# LimitRanges, NetworkPolicy, RBAC
###############################################################################

resource "kubernetes_namespace_v1" "ns" {
  for_each = var.namespaces

  metadata {
    name = each.key
    labels = {
      "pod-security.kubernetes.io/enforce" = each.value.pod_security_enforce
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }

  depends_on = [aws_eks_node_group.general]
}

resource "kubernetes_resource_quota_v1" "ns" {
  for_each = var.namespaces

  metadata {
    name      = "default-quota"
    namespace = kubernetes_namespace_v1.ns[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"           = each.value.requests_cpu
      "requests.memory"        = each.value.requests_memory
      "limits.cpu"             = each.value.limits_cpu
      "limits.memory"          = each.value.limits_memory
      "pods"                   = each.value.pods
      "persistentvolumeclaims" = each.value.pvcs
      "services.loadbalancers" = "0"
      "services.nodeports"     = "0"
    }
  }
}

resource "kubernetes_limit_range_v1" "ns" {
  for_each = var.namespaces

  metadata {
    name      = "default-limits"
    namespace = kubernetes_namespace_v1.ns[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# Default deny (ingress + egress) ...
resource "kubernetes_network_policy_v1" "default_deny" {
  for_each = var.namespaces

  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.ns[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }

  depends_on = [aws_eks_addon.vpc_cni]
}

# ... then allow DNS only. Add per-namespace allow rules (GitLab, registry, DB...) in Git.
resource "kubernetes_network_policy_v1" "allow_dns" {
  for_each = var.namespaces

  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace_v1.ns[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }

  depends_on = [aws_eks_addon.vpc_cni]
}

# RBAC: each team group (from its Access Entry) gets the built-in "edit" role
# only in the namespaces it owns. Admins are cluster-admin via Access Entries.
locals {
  team_bindings = merge([
    for team, cfg in var.team_access : {
      for ns in cfg.namespaces : "${team}/${ns}" => { team = team, namespace = ns }
    }
  ]...)
}

resource "kubernetes_role_binding_v1" "team_edit" {
  for_each = local.team_bindings

  metadata {
    name      = "ex-team-${each.value.team}-edit"
    namespace = each.value.namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "ex-team-${each.value.team}"
  }

  depends_on = [kubernetes_namespace_v1.ns]
}

###############################################################################
# Outputs
###############################################################################

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  value = aws_eks_cluster.this.version
}

output "node_role_arn" {
  value = aws_iam_role.node.arn
}

output "kms_key_arn" {
  value = aws_kms_key.eks.arn
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.region}"
}
