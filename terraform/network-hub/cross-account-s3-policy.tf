/*
# Cross-account S3 access policy for spoke Terraform OIDC roles to manage shared Terraform state.

data "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-network-hub-082787299790"
}

locals {
  organization_id = element(split("/", var.organization_arn), 1)
}

data "aws_iam_policy_document" "cross_account_s3_access" {
  statement {
    sid    = "AllowSpokeReadWriteState"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [local.organization_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/GitHubAction-Terraform-Role"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = [
      "${data.aws_s3_bucket.terraform_state.arn}/terraform-*.tfstate",
    ]
  }

  statement {
    sid    = "AllowSpokeListBucket"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [local.organization_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/GitHubAction-Terraform-Role"]
    }

    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning",
    ]

    resources = [
      data.aws_s3_bucket.terraform_state.arn,
    ]
  }

  statement {
    sid    = "AllowSpokeStateLocking"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [local.organization_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:role/GitHubAction-Terraform-Role"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = [
      "${data.aws_s3_bucket.terraform_state.arn}/terraform-*.tfstate.tflock",
    ]
  }
}

resource "aws_s3_bucket_policy" "cross_account_access" {
  bucket = data.aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.cross_account_s3_access.json
}
*/
