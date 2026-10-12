variable "cluster_name" {
  type = string
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt EBS volumes created by the StorageClass."
  type        = string
}

variable "storage_class_name" {
  type    = string
  default = "ebs-gp3"
}
