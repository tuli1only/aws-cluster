output "storage_class_name" {
  value = kubernetes_storage_class_v1.ebs_gp3.metadata[0].name
}

output "addons" {
  value = [
    aws_eks_addon.coredns.addon_name,
    aws_eks_addon.ebs_csi.addon_name,
  ]
}
