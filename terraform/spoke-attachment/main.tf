locals {
  spoke_routes = flatten([
    for route_table_id in var.spoke_route_table_ids : [
      for destination_cidr in var.destination_cidrs : {
        key            = "${route_table_id}_${replace(destination_cidr, "/", "-")}"
        route_table_id = route_table_id
        cidr_block     = destination_cidr
      }
    ]
  ])
}

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  provider           = aws.spoke
  subnet_ids         = var.spoke_subnet_ids
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = var.spoke_vpc_id
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

resource "aws_route" "spoke_to_tgw" {
  provider = aws.spoke
  for_each = {
    for route in local.spoke_routes : route.key => route
  }

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.cidr_block
  transit_gateway_id     = var.transit_gateway_id
}
