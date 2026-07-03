# Associate and propagate spoke attachments into the hub spoke route table.
# Remote state data sources (aggregator, audit) are defined in spoke-attachment-tags.tf.

# ── Aggregator spoke ──────────────────────────────────────────────────────────

# resource "aws_ec2_transit_gateway_route_table_association" "aggregator" {
#   transit_gateway_attachment_id  = data.terraform_remote_state.aggregator.outputs.transit_gateway_attachment_id
#   transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
# }

# resource "aws_ec2_transit_gateway_route_table_propagation" "aggregator" {
#   transit_gateway_attachment_id  = data.terraform_remote_state.aggregator.outputs.transit_gateway_attachment_id
#   transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
# }

# ── Audit spoke ───────────────────────────────────────────────────────────────

# resource "aws_ec2_transit_gateway_route_table_association" "audit" {
#   transit_gateway_attachment_id  = data.terraform_remote_state.audit.outputs.transit_gateway_attachment_id
#   transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
# }

# resource "aws_ec2_transit_gateway_route_table_propagation" "audit" {
#   transit_gateway_attachment_id  = data.terraform_remote_state.audit.outputs.transit_gateway_attachment_id
#   transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
# }

