# Cross-account S3 access policy for the aggregator account role to manage shared Terraform state.

data "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-network-hub-082787299790"
}

data "aws_iam_policy_document" "cross_account_s3_access" {
  statement {
    sid    = "AllowAggregatorReadWriteState"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::334296258026:role/GitHubAction-Terraform-Role", # Aggregator account OIDC role used by terraform-aggregator-account workflow
      ]
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
    sid    = "AllowAggregatorListBucket"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::334296258026:role/GitHubAction-Terraform-Role", # Aggregator account OIDC role used by terraform-aggregator-account workflow
      ]
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
    sid    = "AllowAggregatorStateLocking"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::334296258026:role/GitHubAction-Terraform-Role", # Aggregator account OIDC role used by terraform-aggregator-account workflow
      ]
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
