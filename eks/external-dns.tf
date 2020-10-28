provider "tls" {
  version = "~> 3.0"
}

data "aws_caller_identity" "current" {}

data "tls_certificate" "cluster" {
  url = data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}
resource "aws_iam_openid_connect_provider" "main" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = concat([data.tls_certificate.cluster.certificates.0.sha1_fingerprint])
  url             = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer

  lifecycle {
    ignore_changes = [thumbprint_list]
  }
}

data "aws_iam_policy_document" "eks-cluster-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.main.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.main.arn]
      type        = "Federated"
    }
  }
}

resource "alks_iamtrustrole" "external-dns-role" {
  name      = "${var.name}-external-dns-role"
  type      = "Inner Account"
  trust_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/acct-managed/ExternalDNSTrustRole"
}

resource "aws_iam_role_policy_attachment" "ExternalDNSRoute53PolicyAttachment" {
  policy_arn = aws_iam_policy.AmazonEKSClusterRoute53Policy.arn
  role       = alks_iamtrustrole.external-dns-role.name
}

resource "kubernetes_cluster_role" "external-dns" {
  metadata {
    name      = "external-dns"
    namespace = "external-dns"
  }

  rule {
    api_groups = ["", "extensions"]
    resources  = ["services", "pods", "nodes", "ingresses"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "external-dns-viewer" {
  metadata {
    name      = "external-dns-viewer"
    namespace = "external-dns"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.external-dns.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.external-dns.metadata[0].name
    namespace = "external-dns"
  }

  depends_on = [kubernetes_cluster_role.external-dns]
}

resource "kubernetes_service_account" "external-dns" {
  automount_service_account_token = true
  metadata {
    name      = "external-dns"
    namespace = "external-dns"
    annotations = {
      "eks.amazonaws.com/role-arn" = alks_iamtrustrole.external-dns-role.arn
    }
  }
}

resource "kubernetes_deployment" "external-dns" {
  metadata {
    name      = "external-dns"
    namespace = "external-dns"
  }

  spec {
    
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        "app" = "external-dns"
      }
    }

    template {
      metadata {
        labels = {
          "app" = "external-dns"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.external-dns.metadata[0].name

        container {
          name              = "external-dns"
          image             = "k8s.gcr.io/external-dns/external-dns:latest"
          image_pull_policy = "Always"

          args = [
            "--source=service",
            "--source=ingress",
            "--domain-filter=eks-test.coxautoinc.com",
            "--provider=aws",
            "--policy=sync",
            "--aws-zone-type=public",
            "--registry=txt"
          ]
        }

        security_context {
          fs_group = 65534
        }
      }
    }
  }

  depends_on = [kubernetes_cluster_role_binding.external-dns-viewer]
}
