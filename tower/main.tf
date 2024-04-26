locals {
  name   = "crossform-tower"
  domain = "tower.crossform.io"
}

#resource "aws_iam_policy" "additional" {
#  name = "${local.name}-additional"
#
#  policy = jsonencode({
#    Version   = "2012-10-17"
#    Statement = [
#      {
#        Action = [
#          "ec2:Describe*",
#        ]
#        Effect   = "Allow"
#        Resource = "*"
#      },
#    ]
#  })
#}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = local.name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access          = true
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  # You require a node group to schedule coredns which is critical for running correctly internal DNS.
  # If you want to use only fargate you must follow docs `(Optional) Update CoreDNS`
  # available under https://docs.aws.amazon.com/eks/latest/userguide/fargate-getting-started.html


  #  fargate_profile_defaults = {
  #    iam_role_additional_policies = {
  #      additional = aws_iam_policy.additional.arn
  #    }
  #  }

  fargate_profiles = {
    default = {
      name      = "default"
      selectors = [
        {
          namespace = "*"
        }
      ]
    }
  }

  cluster_addons = {
    kube-proxy = {}
    vpc-cni    = {}
    coredns    = {
      configuration_values = jsonencode({
        computeType = "Fargate"
      })
    }
  }
}

data "aws_region" "current" {}

module "domain" {
  source = "./domain"
  zone   = local.domain
  vpc_id = module.vpc.vpc_id

}

module "alb" {
  source                             = "./alb"
  aws_alb_ingress_controller_version = "2.4.1"
  k8s_namespace                      = "kube-system"
  aws_region_name                    = data.aws_region.current.name
  k8s_cluster_name                   = module.eks.cluster_name
  oidc_url                           = module.eks.cluster_oidc_issuer_url
  oidc_arn                           = module.eks.oidc_provider_arn
  k8s_replicas                       = 1
  vpc_id                             = module.vpc.vpc_id
}

module "irsa_external_dns" {
  source         = "./irsa"
  name           = "externaldns"
  cluster_name   = module.eks.cluster_name
  namespace      = "kube-system"
  serviceaccount = "external-dns"
  oidc_url       = module.eks.cluster_oidc_issuer_url
  oidc_arn       = module.eks.oidc_provider_arn
  policy_arns    = ["arn:aws:iam::aws:policy/AmazonRoute53FullAccess"]
}

resource "helm_release" "external_dns" {
  name             = "external-dns"
  chart            = "external-dns"
  version          = "7.2.0"
  repository       = "https://charts.bitnami.com/bitnami"
  namespace        = "kube-system"
  create_namespace = false
  cleanup_on_fail  = true

  dynamic "set" {
    for_each = {
      "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn" = module.irsa_external_dns.arn
      "provider" : "aws"
      "registry" : "txt"
      "txtOwnerId" : "crossform"
      "txtPrefix" : "external-dns"
      "policy" : "sync"
      "publishInternalServices" : "true"
      "triggerLoopOnEvent" : "true"
      "extraArgs.annotation-filter=external-dns.kubernetes.io/enable" : "true"
      "logLevel" : "debug"
      "interval" : "10m"
      "triggerLoopOnEvent" : "true"
    }
    content {
      name  = set.key
      value = set.value
    }
  }
}

module "argo" {
  source       = "./argo"
  domain       = local.domain
  cluster_name = module.eks.cluster_name
  region       = data.aws_region.current.name
  argo_repo    = "git@github.com:zefir01/crossform.git"
  oidc_url     = module.eks.cluster_oidc_issuer_url
  oidc_arn     = module.eks.oidc_provider_arn
  argo_branch  = "main"
  argo_ssh_key = file("argo-git")
}

resource "helm_release" "crossplane" {
  name             = "crossplane"
  chart            = "crossplane"
  version          = "1.15.2"
  repository       = "https://charts.crossplane.io/stable"
  namespace        = "crossplane-system"
  create_namespace = true
  cleanup_on_fail  = true
  values           = [
    <<EOF
args:
  - --enable-environment-configs=true
  - --enable-composition-functions-extra-resources=true
  - --enable-ssa-claims
registry: index.docker.io
EOF
  ]
}

resource "helm_release" "crossform" {
  depends_on = [helm_release.crossplane]
  name       = "crossform"
  chart      = "../helm/crossform"
}

module "irsa_provider_aws" {
  source         = "./irsa"
  name           = "crossplane"
  cluster_name   = module.eks.cluster_name
  namespace      = "crossplane-system"
  serviceaccount = "crossplane-provider-aws"
  oidc_url       = module.eks.cluster_oidc_issuer_url
  oidc_arn       = module.eks.oidc_provider_arn
  policy_arns    = ["arn:aws:iam::aws:policy/AdministratorAccess"]
}

resource "kubernetes_manifest" "deployment_config_aws" {
  depends_on = [helm_release.crossplane]
  manifest   = {
    apiVersion = "pkg.crossplane.io/v1beta1"
    kind       = "DeploymentRuntimeConfig"
    metadata   = {
      name = "provider-aws"
    }
    spec = {
      serviceAccountTemplate = {
        metadata = {
          name        = "crossplane-provider-aws"
          annotations = {
            "eks.amazonaws.com/role-arn" = module.irsa_provider_aws.arn
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "provider_aws" {
  depends_on = [kubernetes_manifest.deployment_config_aws]
  manifest   = {
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata   = {
      name = "provider-aws"
    }
    spec = {
      runtimeConfigRef = {
        name = "provider-aws"
      }
      package = "xpkg.upbound.io/crossplane-contrib/provider-aws:v0.47.2"
    }
  }
}

resource "kubernetes_secret_v1" "crossform_repo" {
  depends_on = [helm_release.crossplane]
  metadata {
    name      = "crossform-repo"
    namespace = "crossplane-system"
    labels    = {
      "crossform.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    repository    = "git@github.com:zefir01/crossform.git"
    sshPrivateKey = file("argo-git")
  }
}
