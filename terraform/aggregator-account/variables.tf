# ── General ───────────────────────────────────────────────────────────────────

variable "region" {
  description = "AWS region for the spoke VPC and TGW attachment"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment tag value"
  type        = string
  default     = "production"
}

# ── Account profiles ──────────────────────────────────────────────────────────

variable "hub_profile" {
  description = "AWS CLI profile for the Network-hub account"
  type        = string
}

variable "spoke_profile" {
  description = "AWS CLI profile for the spoke account"
  type        = string
}

variable "account_name" {
  description = "Human-readable account name used in tags (e.g. 'Audit')"
  type        = string
}

# ── Network-hub inputs ────────────────────────────────────────────────────────

variable "transit_gateway_id" {
  description = "Transit Gateway ID from the network-hub stack"
  type        = string
}

variable "hub_spoke_route_table_id" {
  description = "TGW route table ID used for spoke associations (from network-hub stack)"
  type        = string
}

# ── Spoke VPC ─────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the spoke VPC"
  type        = string
}

variable "vpc_name" {
  description = "Name tag for the VPC and its resources"
  type        = string
}

variable "tgw_subnet_cidrs" {
  description = "CIDR blocks for the two TGW attachment subnets (one per AZ)"
  type        = list(string)
  validation {
    condition     = length(var.tgw_subnet_cidrs) == 2
    error_message = "Exactly two TGW subnet CIDRs must be provided for HA across two AZs."
  }
}

variable "tgw_subnet_azs" {
  description = "Availability zones for the two TGW attachment subnets"
  type        = list(string)
  validation {
    condition     = length(var.tgw_subnet_azs) == 2
    error_message = "Exactly two AZs must be provided."
  }
}

# ── TGW Attachment ────────────────────────────────────────────────────────────

variable "destination_cidrs" {
  description = "CIDR blocks to route from the spoke toward TGW (e.g. RFC-1918 supernets)"
  type        = list(string)
}

variable "attachment_name" {
  description = "Name tag for the TGW VPC attachment"
  type        = string
}
