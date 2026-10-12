variable "namespaces" {
  description = "Governed namespaces (ex-platform-*, ex-app-<team>) with Pod Security level and quota."
  type = map(object({
    pod_security_enforce = string # privileged | baseline | restricted
    requests_cpu         = string
    requests_memory      = string
    limits_cpu           = string
    limits_memory        = string
    pods                 = string
    pvcs                 = string
  }))
}

variable "team_access" {
  description = "Same map given to the cluster module. Each team gets the built-in edit role in its namespaces."
  type = map(object({
    principal_arn = string
    namespaces    = list(string)
  }))
  default = {}
}
