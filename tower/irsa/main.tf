resource "random_string" "random" {
  length  = 8
  special = false
  lower   = true
  numeric = true
  upper   = false
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

#module "irsa" {
#  source         = "Young-ook/eks/aws//modules/iam-role-for-serviceaccount"
#  name           = "irsa-${var.cluster_name}-${var.name}-${random_string.random.result}"
#  namespace      = var.namespace
#  serviceaccount = var.serviceaccount
#  oidc_url       = replace(var.oidc_url, "https://", "")
#  oidc_arn       = var.oidc_arn
#  policy_arns    = var.policy_arns
#  tags           = var.tags
#}


locals {
  oidc_fully_qualified_subject = format("system:serviceaccount:%s:%s", var.namespace, var.serviceaccount)
}


locals {
  name         = substr("irsa-${var.cluster_name}-${var.name}-${random_string.random.result}", 0, 64)
  default-tags = merge(
    { "Name" = local.name },
  )
}

data "aws_iam_policy_document" "this" {
  dynamic "statement" {
    # https://aws.amazon.com/blogs/security/announcing-an-update-to-iam-role-trust-policy-behavior/
    for_each = var.allow_self_assume_role ? [1] : []

    content {
      sid     = "ExplicitSelfRoleAssumption1"
      effect  = "Allow"
      actions = ["sts:AssumeRole", "sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "AWS"
        identifiers = ["*"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:PrincipalArn"
        values   = [
          "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}"
        ]
      }
    }
  }

  statement {

    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_arn]
    }

    condition {
      test     = "StringLike"
      variable = format("%s:sub", replace(var.oidc_url, "https://", ""))
      values   = [local.oidc_fully_qualified_subject]
    }
    condition {
      test     = var.sa_wildcard ? "StringLike" : "StringEquals"
      variable = format("%s:aud", replace(var.oidc_url, "https://", ""))
      values   = ["sts.amazonaws.com"]
    }


  }
}

resource "aws_iam_role" "irsa" {
  name               = local.name
  path               = "/"
  tags               = merge(local.default-tags, var.tags)
  assume_role_policy = data.aws_iam_policy_document.this.json
}

resource "aws_iam_role_policy_attachment" "irsa" {
  for_each   = {for key, val in var.policy_arns : key => val}
  policy_arn = each.value
  role       = aws_iam_role.irsa.name
}

