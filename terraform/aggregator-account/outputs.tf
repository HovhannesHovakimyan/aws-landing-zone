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

# ── Test instance outputs ─────────────────────────────────────────────────────

output "test_instance_id" {
  description = "ID of the test EC2 instance"
  value       = aws_instance.test.id
}

output "test_instance_private_ip" {
  description = "Private IP of the test EC2 instance"
  value       = aws_instance.test.private_ip
}

output "test_instance_public_ip" {
  description = "Public IP of the test EC2 instance"
  value       = aws_instance.test.public_ip
}

output "app_subnet_ids" {
  description = "IDs of the app-tier subnets"
  value       = aws_subnet.app[*].id
}
