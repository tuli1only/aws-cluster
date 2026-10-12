variable "cluster_name" {
  description = "EKS cluster name (ex-a-eks / ex-b-eks)."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version, e.g. \"1.35\". Must be one EKS supports in standard support."
  type        = string

  validation {
    condition     = can(regex("^1\\.[0-9]{2}$", var.kubernetes_version))
    error_message = "Use the form \"1.35\"."
  }
}

variable "subnet_ids" {
  description = "Private subnets (2+ AZs) for the control plane network interfaces."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the API endpoint publicly. Keep false for the Black/Red networks."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "Allowed CIDRs when endpoint_public_access is true."
  type        = list(string)
  default     = []
}

variable "control_plane_log_types" {
  description = "Control plane log categories sent to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "admin_role_arns" {
  description = "IAM roles that get cluster-admin through EKS Access Entries."
  type        = list(string)
  default     = []
}

variable "team_access" {
  description = "Team IAM principals. Each gets the Kubernetes group ex-team-<key>; RBAC is applied by the governance module."
  type = map(object({
    principal_arn = string
    namespaces    = list(string)
  }))
  default = {}
}
