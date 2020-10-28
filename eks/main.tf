provider "local" {
  version = "~> 1.4"
}

provider "template" {
  version = "~> 2.2"
}

provider "external" {
  version = "~> 2.0"
}
provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.13"
}

data "aws_eks_cluster" "cluster" {
  name = aws_eks_cluster.main.id
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.main.id
}

resource "aws_iam_role_policy" "AmazonEKSClusterCloudWatchMetricsPolicy" {
  name   = "AmazonEKSClusterCloudWatchMetricsPolicy"
  role   = alks_iamrole.eks_cluster_role.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "AmazonEKSClusterNLBPolicy" {
  name   = "AmazonEKSClusterNLBPolicy"
  role   = alks_iamrole.eks_cluster_role.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "elasticloadbalancing:*",
                "ec2:CreateSecurityGroup",
                "ec2:Describe*"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_policy" "AmazonEKSClusterRoute53Policy" {
  name        = "AmazonEKSClusterRoute53Policy"
  path        = "/"
  description = "IAM Policy for EKS Route53"

  policy = jsonencode(
    {
      Version : "2012-10-17"
      Statement : [
        {
          Effect : "Allow"
          Action : [
            "route53:ChangeResourceRecordSets"
          ]
          Resource : [
            "arn:aws:route53:::hostedzone/*"
          ]
        },
        {
          Effect : "Allow",
          Action : [
            "route53:ListHostedZones",
            "route53:ListResourceRecordSets"
          ],
          Resource : [
            "*"
          ]
        }
      ]
    }
  )
}

resource "alks_iamrole" "eks_cluster_role" {
  name                     = "${var.name}-eks-cluster-role"
  type                     = "Amazon EKS" // "eks.amazonaws.com", "eks-fargate-pods.amazonaws.com" services assume-role
  include_default_policies = true         // some policy attachments can be avoided if those are part of this default policies
}
resource "aws_iam_role_policy_attachment" "AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = alks_iamrole.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = alks_iamrole.eks_cluster_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKSClusterRoute53PolicyAttachment" {
  policy_arn = aws_iam_policy.AmazonEKSClusterRoute53Policy.arn
  role       = alks_iamrole.eks_cluster_role.name
}

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.name}-${var.environment}/cluster"
  retention_in_days = 30

  tags = {
    Name        = "${var.name}-${var.environment}-eks-cloudwatch-log-group"
    Environment = var.environment
  }
}

resource "aws_eks_cluster" "main" {
  name     = "${var.name}-${var.environment}"
  role_arn = alks_iamrole.eks_cluster_role.arn

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  vpc_config {
    subnet_ids              = concat(sort(var.public_subnets.ids), sort(var.private_subnets.ids))
    endpoint_private_access = true
  }

  timeouts {
    delete = "30m"
  }

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster,
    aws_iam_role_policy_attachment.AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.AmazonEKSServicePolicy
  ]
}

resource "alks_iamrole" "eks_node_group_role" {
  name                     = "${var.name}-eks-node-group-role"
  type                     = "Amazon EC2"
  include_default_policies = true
}

resource "aws_iam_role_policy" "certmanager_route53_iam_policy" {
  name = "${var.name}-certmanager_route53_iam_policy"
  role = alks_iamrole.eks_node_group_role.id
  policy = jsonencode(
    {
      Version : "2012-10-17"
      Statement : [
        {
          Effect : "Allow"
          Action : "route53:GetChange"
          Resource : "arn:aws:route53:::change/*"
        },
        {
          Effect : "Allow"
          Action : "route53:ChangeResourceRecordSets"
          Resource : "arn:aws:route53:::hostedzone/*"
        },
        {
          Effect : "Allow"
          Action : "route53:ListHostedZonesByName"
          Resource : "*"
        }
      ]
    }
  )
}
resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = alks_iamrole.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = alks_iamrole.eks_node_group_role.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = alks_iamrole.eks_node_group_role.name
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.name}-${var.environment}-nodegroup"
  node_role_arn   = alks_iamrole.eks_node_group_role.arn
  subnet_ids      = var.private_subnets.ids

  scaling_config {
    desired_size = 2
    max_size     = 4
    min_size     = 2
  }

  tags = {
    Name        = "${var.name}-${var.environment}-nodegroup"
    Environment = var.environment
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}

data "template_file" "kubeconfig" {
  template = file("${path.module}/templates/kubeconfig.tpl")

  vars = {
    kubeconfig_name     = "eks_${aws_eks_cluster.main.name}"
    clustername         = aws_eks_cluster.main.name
    endpoint            = data.aws_eks_cluster.cluster.endpoint
    cluster_auth_base64 = data.aws_eks_cluster.cluster.certificate_authority[0].data
  }
}

resource "local_file" "kubeconfig" {
  content  = data.template_file.kubeconfig.rendered
  filename = pathexpand("${var.kubeconfig_path}/config")
}

output "kubectl_config" {
  description = "Path to new kubectl config file"
  value       = pathexpand("${var.kubeconfig_path}/config")
}

output "cluster_id" {
  description = "ID of the created cluster"
  value       = aws_eks_cluster.main.id
}
