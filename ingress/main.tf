provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.13"
}

provider "kubernetes-alpha" {}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_id
}

data "aws_caller_identity" "current" {}


resource "kubernetes_manifest" "traefik-ingressroutes" {
  provider = kubernetes-alpha

  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "ingressroutes.traefik.containo.us"
    }
    spec = {
      group = "traefik.containo.us"
      names = {
        kind     = "IngressRoute"
        plural   = "ingressroutes"
        singular = "ingressroute"
      }
      scope    = "Namespaced"
      versions = ["v1alpha1"]
    }
  }
}

resource "kubernetes_manifest" "traefik-ingressroutetcps" {
  provider = kubernetes-alpha

  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "ingressroutetcps.traefik.containo.us"
    }
    spec = {
      group = "traefik.containo.us"
      names = {
        kind     = "IngressRouteTCP"
        plural   = "ingressroutetcps"
        singular = "ingressroutetcp"
      }
      scope    = "Namespaced"
      versions = ["v1alpha1"]
    }
  }
}

resource "kubernetes_manifest" "traefik-middlewares" {
  provider = kubernetes-alpha

  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "middlewares.traefik.containo.us"
    }
    spec = {
      group = "traefik.containo.us"
      names = {
        kind     = "Middleware"
        plural   = "middlewares"
        singular = "middleware"
      }
      scope    = "Namespaced"
      versions = ["v1alpha1"]
    }
  }
}

resource "kubernetes_manifest" "traefik-tlsoptions" {
  provider = kubernetes-alpha

  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "tlsoptions.traefik.containo.us"
    }
    spec = {
      group = "traefik.containo.us"
      names = {
        kind     = "TLSOption"
        plural   = "tlsoptions"
        singular = "tlsoption"
      }
      scope    = "Namespaced"
      versions = ["v1alpha1"]
    }
  }
}

resource "kubernetes_manifest" "traefik-services" {
  provider = kubernetes-alpha

  manifest = {
    apiVersion = "apiextensions.k8s.io/v1"
    kind       = "CustomResourceDefinition"
    metadata = {
      name = "traefikservices.traefik.containo.us"
    }
    spec = {
      group = "traefik.containo.us"
      names = {
        kind     = "TraefikService"
        plural   = "traefikservices"
        singular = "traefikservice"
      }
      scope    = "Namespaced"
      versions = ["v1alpha1"]
    }
  }
}

resource "kubernetes_cluster_role" "traefik-ingress-controller" {
  metadata {
    name = "traefik-ingress-controller"
  }

  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "secrets"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses/status"]
    verbs      = ["update"]
  }

  rule {
    api_groups = ["traefik.containo.us"]
    resources  = ["middlewares"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["traefik.containo.us"]
    resources  = ["ingressroutes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["traefik.containo.us"]
    resources  = ["ingressroutetcps"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["traefik.containo.us"]
    resources  = ["tlsoptions"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["traefik.containo.us"]
    resources  = ["traefikservices"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_service_account" "traefik-ingress-controller" {
  automount_service_account_token = true
  metadata {
    name = "traefik-ingress-controller"
  }
}

resource "kubernetes_cluster_role_binding" "traefik-ingress-controller" {
  metadata {
    name = "traefik-ingress-controller"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.traefik-ingress-controller.metadata[0].name
  }
  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account.traefik-ingress-controller.metadata[0].name
  }

  depends_on = [kubernetes_cluster_role.traefik-ingress-controller]
}


resource "kubernetes_deployment" "traefik" {
  metadata {
    name = "traefik"
    labels = {
      "app" = "traefik"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app" = "traefik"
      }
    }

    template {
      metadata {
        labels = {
          "app" = "traefik"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.traefik-ingress-controller.metadata[0].name

        container {
          name  = "traefik"
          image = "traefik:v2.3"

          args = [
            "--api.insecure",
            "--accesslog",
            "--entrypoints.web.Address=:8000",
            "--entrypoints.websecure.Address=:4443",
            "--providers.kubernetescrd",
            "--certificatesresolvers.default.acme.tlschallenge",
            "--certificatesresolvers.default.acme.email=thejoyoflife@gmail.com",
            "--certificatesresolvers.default.acme.storage=acme.json",
            "--certificatesresolvers.default.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory",
            "--tracing.jaeger=true",
            "--tracing.jaeger.gen128Bit",
            "--tracing.jaeger.propagation=b3",
            "--tracing.jaeger.localAgentHostPort=jaeger-agent:6831",
            "--tracing.jaeger.collector.endpoint=http://jaeger-collector:14268/api/traces?format=jaeger.thrift",
            "--metrics.prometheus=true"
          ]

          port {
            name           = "web"
            container_port = 8000
          }

          port {
            name           = "websecure"
            container_port = 4443
          }
        }
      }
    }
  }

  depends_on = [kubernetes_cluster_role_binding.traefik-ingress-controller]
}

resource "kubernetes_service" "traefik" {
  metadata {
    name = "traefik"
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      "external-dns.alpha.kubernetes.io/hostname"         = "*.eks-test.coxautoinc.com"
    }
  }
  spec {
    selector = {
      app = "${kubernetes_deployment.traefik.metadata.0.labels.app}"
    }

    port {
      name        = "web"
      protocol    = "TCP"
      port        = 80
      target_port = "web"
    }

    port {
      name     = "admin"
      protocol = "TCP"
      port     = 8080
    }

    port {
      name        = "websecure"
      protocol    = "TCP"
      port        = 443
      target_port = "websecure"
    }

    type = "LoadBalancer"
  }
}

