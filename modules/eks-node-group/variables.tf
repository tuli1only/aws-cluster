variable "cluster_name" {
  type = string
}

variable "node_group_name" {
  description = "e.g. general-platform or data-ai."
  type        = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "instance_types" {
  type    = list(string)
  default = ["m7i.2xlarge"] # 8 vCPU / 32 GiB
}

variable "desired_size" {
  type = number
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "disk_size_gb" {
  type    = number
  default = 100
}

variable "ami_type" {
  type    = string
  default = "AL2023_x86_64_STANDARD"
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "max_unavailable" {
  description = "Nodes that may be replaced at once during updates."
  type        = number
  default     = 1
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "taints" {
  description = "Taints, effect is NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE."
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}
