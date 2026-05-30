# Tag TGW attachments from the hub account perspective so they show named in the
# hub account's Console view. Spoke accounts tag their own side; the TGW owner
# (hub) must apply tags separately for them to appear when browsing the hub account.

# ── Aggregator spoke ──────────────────────────────────────────────────────────

data "terraform_remote_state" "aggregator" {
  backend = "s3"
  config = {
    bucket  = "terraform-network-hub-082787299790"
    key     = "terraform-aggregator-account.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

resource "aws_ec2_tag" "aggregator_attachment_name" {
  resource_id = data.terraform_remote_state.aggregator.outputs.transit_gateway_attachment_id
  key         = "Name"
  value       = data.terraform_remote_state.aggregator.outputs.transit_gateway_attachment_name
}

# ── Audit spoke ───────────────────────────────────────────────────────────────

data "terraform_remote_state" "audit" {
  backend = "s3"
  config = {
    bucket  = "terraform-network-hub-082787299790"
    key     = "terraform-audit-account.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

resource "aws_ec2_tag" "audit_attachment_name" {
  resource_id = data.terraform_remote_state.audit.outputs.transit_gateway_attachment_id
  key         = "Name"
  value       = data.terraform_remote_state.audit.outputs.transit_gateway_attachment_name
}
