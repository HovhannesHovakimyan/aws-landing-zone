/*
# AWS RAM Resource Share for sharing Transit Gateway with Organization
resource "aws_ram_resource_share" "tgw_share" {
  name                      = "hub-tgw-resource-share"
  allow_external_principals = false

  tags = {
    Name        = "hub-tgw-resource-share"
    Description = "Resource share for Transit Gateway with AWS Organization"
  }
}

# Associate Transit Gateway with Resource Share
resource "aws_ram_resource_association" "tgw_association" {
  resource_arn       = aws_ec2_transit_gateway.hub.arn
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
}

# Share Transit Gateway with AWS Organization
resource "aws_ram_principal_association" "organization" {
  principal          = trimspace(var.organization_arn)
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
}
*/
