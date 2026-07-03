locals {
  network_hub_state = data.terraform_remote_state.network_hub.outputs

  spoke_routes = {
    for cidr in var.destination_cidrs :
    replace(cidr, "/", "-") => cidr
  }
}

data "terraform_remote_state" "network_hub" {
  backend = "s3"
  config = {
    bucket = var.network_hub_state_bucket
    key    = var.network_hub_state_key
    region = var.network_hub_state_region
  }
}

/*
# ── Spoke VPC ─────────────────────────────────────────────────────────────────

resource "aws_vpc" "spoke" {
  provider             = aws.spoke
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.vpc_name
  }
}

# TGW attachment subnets — one per AZ for high availability
resource "aws_subnet" "tgw" {
  provider          = aws.spoke
  count             = 2
  vpc_id            = aws_vpc.spoke.id
  cidr_block        = var.tgw_subnet_cidrs[count.index]
  availability_zone = var.tgw_subnet_azs[count.index]

  tags = {
    Name = "${var.vpc_name}-tgw-${var.tgw_subnet_azs[count.index]}"
  }
}

resource "aws_route_table" "tgw" {
  provider = aws.spoke
  vpc_id   = aws_vpc.spoke.id

  tags = {
    Name = "${var.vpc_name}-tgw-rt"
  }
}

resource "aws_route_table_association" "tgw" {
  provider       = aws.spoke
  count          = 2
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw.id
}

# ── TGW Attachment ─────────────────────────────────────────────────────────────

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  provider           = aws.spoke
  subnet_ids         = aws_subnet.tgw[*].id
  transit_gateway_id = local.network_hub_state.transit_gateway_id
  vpc_id             = aws_vpc.spoke.id
  dns_support        = "enable"

  tags = {
    Name = var.attachment_name
  }
}

# Association/propagation for shared TGW route tables is managed by the TGW
# owner account (network-hub). Spoke account workflow creates only attachment
# and local VPC routes to the shared TGW.
resource "aws_route" "spoke_to_tgw" {
  provider               = aws.spoke
  for_each               = local.spoke_routes
  route_table_id         = aws_route_table.tgw.id
  destination_cidr_block = each.value
  transit_gateway_id     = local.network_hub_state.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}
*/
