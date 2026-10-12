variable "region" {
  description = "AWS region. Confirm m7i.2xlarge is offered there."
  type        = string
}

variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  description = "Check available versions: aws eks describe-cluster-versions --region <region>"
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets in 2+ AZs, sized for pod IPs (T09)."
  type        = list(string)
}

variable "endpoint_public_access" {
  type    = bool
  default = false
}

variable "public_access_cidrs" {
  type    = list(string)
  default = []
}

variable "admin_role_arns" {
  type    = list(string)
  default = []
}

variable "team_access" {
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

variable "namespaces" {
  type = map(object({
    pod_security_enforce = string
    requests_cpu         = string
    requests_memory      = string
    limits_cpu           = string
    limits_memory        = string
    pods                 = string
    pvcs                 = string
  }))
  default = {
    "ex-platform-ci" = {
      pod_security_enforce = "baseline" # use "restricted" if builds are rootless
      requests_cpu         = "8"
      requests_memory      = "16Gi"
      limits_cpu           = "16"
      limits_memory        = "32Gi"
      pods                 = "50"
      pvcs                 = "0" # stateless runners
    }
  }
}

variable "lbc_chart_version" {
  description = "Pin the Load Balancer Controller chart version (null = latest)."
  type        = string
  default     = null
}

variable "control_plane_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
