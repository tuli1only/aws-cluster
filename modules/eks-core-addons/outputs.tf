output "addons" {
  value = [
    aws_eks_addon.pod_identity_agent.addon_name,
    aws_eks_addon.vpc_cni.addon_name,
    aws_eks_addon.kube_proxy.addon_name,
  ]
}
