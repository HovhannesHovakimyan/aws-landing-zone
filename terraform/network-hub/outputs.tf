# Transit Gateway Outputs
output "transit_gateway_id" {
  description = "ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.hub.id
}

output "transit_gateway_arn" {
  description = "ARN of the Transit Gateway"
  value       = aws_ec2_transit_gateway.hub.arn
}

output "transit_gateway_asn" {
  description = "ASN of the Transit Gateway"
  value       = aws_ec2_transit_gateway.hub.amazon_side_asn
}

output "transit_gateway_owner_id" {
  description = "AWS Account ID of the Transit Gateway owner"
  value       = aws_ec2_transit_gateway.hub.owner_id
}

# Transit Gateway Route Table Outputs
output "transit_gateway_spoke_route_table_id" {
  description = "ID of the spoke Transit Gateway route table"
  value       = aws_ec2_transit_gateway_route_table.spoke.id
}

# Resource Share Outputs
output "resource_share_arn" {
  description = "ARN of the RAM Resource Share for Transit Gateway"
  value       = aws_ram_resource_share.tgw_share.arn
}

output "resource_share_id" {
  description = "ID of the RAM Resource Share"
  value       = aws_ram_resource_share.tgw_share.id
}

output "resource_share_name" {
  description = "Name of the RAM Resource Share"
  value       = aws_ram_resource_share.tgw_share.name
}

output "organization_arn" {
  description = "Organization ARN with which Transit Gateway is shared"
  value       = var.organization_arn
}
