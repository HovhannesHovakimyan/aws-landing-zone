locals {
  spoke_routes = {
    for cidr in var.destination_cidrs :
    replace(cidr, "/", "-") => cidr
  }
}

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
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.spoke.id
  dns_support        = "enable"

  tags = {
    Name = var.attachment_name
  }
}

resource "aws_ec2_transit_gateway_route_table_association" "spoke" {
  provider                       = aws.hub
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
  transit_gateway_route_table_id = var.hub_spoke_route_table_id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "spoke" {
  provider                       = aws.hub
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.spoke.id
  transit_gateway_route_table_id = var.hub_spoke_route_table_id
}

# Add routes in the spoke route table so traffic destined for other accounts
# is forwarded through the TGW
resource "aws_route" "spoke_to_tgw" {
  provider               = aws.spoke
  for_each               = local.spoke_routes
  route_table_id         = aws_route_table.tgw.id
  destination_cidr_block = each.value
  transit_gateway_id     = var.transit_gateway_id
}
