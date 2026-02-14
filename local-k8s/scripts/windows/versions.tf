terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.5.1"
    }
    external = {
      source  = "hashicorp/external"
      version = "2.3.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.24.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.12.1"
    }
  }
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/config-multipass")
}

provider "helm" {
  kubernetes {
    config_path = pathexpand("~/.kube/config-multipass")
  }
}
