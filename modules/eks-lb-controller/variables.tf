variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "chart_version" {
  description = "aws-load-balancer-controller Helm chart version. Pin it (null = latest)."
  type        = string
  default     = null
}

variable "replica_count" {
  type    = number
  default = 2
}
