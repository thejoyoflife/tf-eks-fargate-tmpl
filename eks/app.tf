resource "kubernetes_service" "main" {
  metadata {
    name      = "service-2048"
    namespace = "default"
  }
  spec {
    selector = {
      app = "${kubernetes_deployment.main.metadata.0.labels.app}"
    }
    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "NodePort"
  }
}

resource "kubernetes_deployment" "main" {
  metadata {
    name      = "deployment-2048"
    namespace = "default"
    labels    = {
        app = "2048"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "2048"
      }
    }

    template {
      metadata {
        labels = {
          app = "2048"
        }
      }

      spec {
        container {
          image = "alexwhen/docker-2048"
          name  = "2048"
        }
      }
    }
  }
}