output "transit_gateway_attachment_id" {
  description = "Transit Gateway attachment ID for the spoke VPC"
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke.id
}

output "transit_gateway_attachment_arn" {
  description = "Transit Gateway attachment ARN for the spoke VPC"
  value       = aws_ec2_transit_gateway_vpc_attachment.spoke.arn
}

output "associated_route_table_id" {
  description = "TGW route table where the spoke attachment is associated"
  value       = var.hub_spoke_route_table_id
}
