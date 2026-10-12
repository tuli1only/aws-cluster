# Hierarchical governance: namespaces > Pod Security > quotas > network rules > RBAC.

resource "kubernetes_namespace_v1" "ns" {
  for_each = var.namespaces

  metadata {
    name = each.key
    labels = {
      "pod-security.kubernetes.io/enforce" = each.value.pod_security_enforce
      "pod-security.kubernetes.io/warn"    = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
    }
  }
}

resource "kubernetes_resource_quota_v1" "ns" {
  for_each = var.namespaces

  metadata {
    name      = "default-quota"
    namespace = kubernetes_namespace_v1.ns[each.key].metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"           = each.value.requests_cpu
      "requests.memory"        = each.value.requests_memory
      "limits.cpu"             = each.value.limits_cpu
      "limits.memory"          = each.value.limits_memory
      "pods"                   = each.value.pods
      "persistentvolumeclaims" = each.value.pvcs
      "services.loadbalancers" = "0"
      "services.nodeports"     = "0"
    }
  }
}

resource "kubernetes_limit_range_v1" "ns" {
  for_each = var.namespaces

  metadata {
    name      = "default-limits"
    namespace = kubernetes_namespace_v1.ns[each.key].metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "500m"
        memory = "512Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}

# Default deny, ingress and egress ...
resource "kubernetes_network_policy_v1" "default_deny" {
  for_each = var.namespaces

  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace_v1.ns[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# ... then allow DNS only. Add specific allow rules (GitLab, registry, ...) per namespace in Git.
resource "kubernetes_network_policy_v1" "allow_dns" {
  for_each = var.namespaces

  metadata {
    name      = "allow-dns-egress"
    namespace = kubernetes_namespace_v1.ns[each.key].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# ---- RBAC: team group -> edit role, only inside the team's namespaces ----

locals {
  team_bindings = merge([
    for team, cfg in var.team_access : {
      for ns in cfg.namespaces : "${team}/${ns}" => {
        team      = team
        namespace = ns
      }
    }
  ]...)
}

resource "kubernetes_role_binding_v1" "team_edit" {
  for_each = local.team_bindings

  metadata {
    name      = "ex-team-${each.value.team}-edit"
    namespace = kubernetes_namespace_v1.ns[each.value.namespace].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "edit"
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "ex-team-${each.value.team}"
  }

  lifecycle {
    precondition {
      condition     = contains(keys(var.namespaces), each.value.namespace)
      error_message = "A team in team_access refers to a namespace that is not defined in 'namespaces'. Add it there first."
    }
  }
}
