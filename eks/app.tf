/*
 For demo purposes we deploy a small app using the kubernetes_ingress ressource
 and a fargate profile
*/


resource "aws_iam_role_policy_attachment" "AmazonEKSFargatePodExecutionRolePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = alks_iamrole.fargate_pod_execution_role.name
}

resource "alks_iamrole" "fargate_pod_execution_role" {
  name                     = "${var.name}-eks-fargate-pod-execution-role"
  type                     = "Amazon EKS"
  include_default_policies = true
  enable_alks_access       = false
}

resource "aws_eks_fargate_profile" "main" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "fp-default"
  pod_execution_role_arn = alks_iamrole.fargate_pod_execution_role.arn
  subnet_ids             = var.private_subnets.*.id

  selector {
    namespace = "default"
  }

  selector {
    namespace = "2048-game"
  }

  timeouts {
    create = "30m"
    delete = "60m"
  }
}

resource "kubernetes_namespace" "example" {
  metadata {
    labels = {
      app = "2048"
    }

    name = "2048-game"
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "deployment-2048"
    namespace = "2048-game"
    labels = {
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

          port {
            container_port = 80
          }
        }
      }
    }
  }

  depends_on = [aws_eks_fargate_profile.main]
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "service-2048"
    namespace = "2048-game"
  }
  spec {
    selector = {
      app = "2048"
    }

    port {
      port        = 80
      target_port = 80
      protocol    = "TCP"
    }

    type = "NodePort"
  }

  depends_on = [kubernetes_deployment.app]
}

resource "kubernetes_ingress" "app" {
  metadata {
    name      = "2048-ingress"
    namespace = "2048-game"
    annotations = {
      "kubernetes.io/ingress.class"           = "alb"
      "alb.ingress.kubernetes.io/scheme"      = "internet-facing"
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
    labels = {
      "app" = "2048-ingress"
    }
  }

  spec {
    rule {
      http {
        path {
          path = "/*"
          backend {
            service_name = "service-2048"
            service_port = 80
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service.app]
}
