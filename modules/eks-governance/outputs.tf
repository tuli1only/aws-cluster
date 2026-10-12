output "namespaces" {
  value = keys(kubernetes_namespace_v1.ns)
}
