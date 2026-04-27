# Cross-account S3 access policy for spoke accounts to read/write state files
# This allows the aggregator-account (and future spoke accounts) to access Terraform state
# stored in the network-hub S3 bucket.

# Policy statement for spoke account OIDC role to access state files
data "aws_iam_policy_document" "cross_account_s3_access" {
  statement {
    sid    = "AllowSpokesReadWriteState"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::612827969911:role/GitHubAction-Terraform-Role", # audit account (aggregator)
        # Add more spoke account OIDC role ARNs here as you add more spokes
      ]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = [
      "${aws_s3_bucket.terraform_state.arn}/terraform-*.tfstate",
    ]
  }

  statement {
    sid    = "AllowSpokesListBucket"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::612827969911:role/GitHubAction-Terraform-Role",
      ]
    }

    actions = [
      "s3:ListBucket",
      "s3:GetBucketVersioning",
    ]

    resources = [
      aws_s3_bucket.terraform_state.arn,
    ]
  }

  statement {
    sid    = "AllowSpokesStateLocking"
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::612827969911:role/GitHubAction-Terraform-Role",
      ]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.terraform_state.arn}/.terraform.lock.hcl",
    ]
  }
}

resource "aws_s3_bucket_policy" "cross_account_access" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.cross_account_s3_access.json
}
