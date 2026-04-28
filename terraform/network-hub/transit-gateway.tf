# AWS EC2 Transit Gateway for Hub-and-Spoke Network Architecture
resource "aws_ec2_transit_gateway" "hub" {
  description                     = "Transit Gateway for Hub-and-Spoke network architecture"
  amazon_side_asn                 = 64512
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  auto_accept_shared_attachments  = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"
  transit_gateway_cidr_blocks     = []

  tags = {
    Name        = "hub-transit-gateway"
    Description = "Primary Transit Gateway for hub-and-spoke architecture"
  }
}

# Transit Gateway Route Table (Default)
resource "aws_ec2_transit_gateway_route_table" "default" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id

  tags = {
    Name = "hub-default-route-table"
  }
}

# Transit Gateway Route Table for Spoke VPCs
resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.hub.id

  tags = {
    Name = "hub-spoke-route-table"
  }
}
