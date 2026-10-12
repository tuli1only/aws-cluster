output "cluster_name" {
  value = module.cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.cluster.cluster_endpoint
}

output "cluster_version" {
  value = module.cluster.cluster_version
}

output "namespaces" {
  value = module.governance.namespaces
}

output "storage_class" {
  value = module.node_addons.storage_class_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.cluster.cluster_name} --region ${var.region}"
}
