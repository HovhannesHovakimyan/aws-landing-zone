variable "region" {
  description = "AWS region for the TGW and spoke VPC"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment tag value"
  type        = string
  default     = "production"
}

variable "hub_profile" {
  description = "AWS CLI profile for the Network-hub account"
  type        = string
}

variable "spoke_profile" {
  description = "AWS CLI profile for the spoke account"
  type        = string
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID from the Network-hub stack"
  type        = string
}

variable "hub_spoke_route_table_id" {
  description = "Transit Gateway route table ID used for spoke associations"
  type        = string
}

variable "spoke_vpc_id" {
  description = "VPC ID in the spoke account"
  type        = string
}

variable "spoke_subnet_ids" {
  description = "Subnet IDs in the spoke VPC used for TGW attachment"
  type        = list(string)
}

variable "spoke_route_table_ids" {
  description = "Spoke VPC route table IDs that should route traffic to TGW"
  type        = list(string)
}

variable "destination_cidrs" {
  description = "CIDR blocks that should be routed from spoke VPC route tables to the TGW"
  type        = list(string)
}

variable "attachment_name" {
  description = "Name tag for the TGW attachment"
  type        = string
}
