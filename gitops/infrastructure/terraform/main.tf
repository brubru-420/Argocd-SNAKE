terraform {
  required_version = ">= 1.5"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
  }
}

provider "kubernetes" {}

# Namespaces applicatifs : GERES PAR ARGOCD, on les reference en lecture seule.
# Terraform ne les cree pas (il ne rentre pas en conflit avec ArgoCD).
variable "app_namespaces" {
  type    = list(string)
  default = ["snake-dev", "snake-prod"]
}

data "kubernetes_namespace" "app" {
  for_each = toset(var.app_namespaces)
  metadata { name = each.value }
}

# --- Ressource 100% geree par Terraform : un namespace dedie a l'infra ---
resource "kubernetes_namespace" "infra" {
  metadata {
    name = "snake-infra"
    labels = {
      "app.kubernetes.io/part-of" = "argocd-snake"
      "managed-by"                = "terraform-controller"
    }
  }
}

# RBAC : role lecture seule dans chaque namespace applicatif (existant)
resource "kubernetes_role" "snake_viewer" {
  for_each = data.kubernetes_namespace.app
  metadata {
    name      = "snake-viewer"
    namespace = each.value.metadata[0].name
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }
}

# Network policy : n'autorise que le trafic entrant vers le port 3000
resource "kubernetes_network_policy" "snake" {
  for_each = data.kubernetes_namespace.app
  metadata {
    name      = "snake-allow-http"
    namespace = each.value.metadata[0].name
  }
  spec {
    pod_selector {
      match_labels = { app = "snake" }
    }
    ingress {
      ports {
        port     = 3000
        protocol = "TCP"
      }
    }
    policy_types = ["Ingress"]
  }
}

output "infra_namespace" {
  value = kubernetes_namespace.infra.metadata[0].name
}
