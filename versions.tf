terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.75.0, < 1.0.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.7.0, < 1.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.31.0, < 3.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.14.0, < 3.0.0"
    }
  }
}
