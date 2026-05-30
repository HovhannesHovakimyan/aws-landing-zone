output "vpc_id" {
  description = "ID of the spoke VPC"
  value       = aws_vpc.spoke.id
}

output "vpc_cidr" {
  description = "CIDR block of the spoke VPC"
  value       = aws_vpc.spoke.cidr_block
}

output "tgw_subnet_ids" {
  description = "IDs of the TGW attachment subnets"
  value       = aws_subnet.tgw[*].id
}

output "tgw_route_table_id" {
  description = "ID of the route table associated with TGW subnets"
  value       = aws_route_table.tgw.id
}

output "transit_gateway_attachment_id" {
  description = "Transit Gateway attachment ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke.id
}

output "transit_gateway_attachment_arn" {
  description = "Transit Gateway attachment ARN"
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke.arn
}

output "transit_gateway_attachment_name" {
  description = "Name tag of the TGW attachment (single source of truth for hub-side tagging)"
  value       = var.attachment_name
}
