terraform {
  required_providers {
    alks = {
      source = "coxautoinc.com/engineering-enablement/alks"
    }
    kubernetes-alpha = {
      source  = "hashicorp/kubernetes-alpha"
      version = "0.2.1"
    }
  }
}
