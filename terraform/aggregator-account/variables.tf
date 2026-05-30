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
  description = "Optional AWS CLI profile for network-hub account (kept for compatibility)"
  type        = string
  default     = null
  nullable    = true
}

variable "spoke_profile" {
  description = "AWS CLI profile for the spoke account"
  type        = string
  default     = null
  nullable    = true
}

variable "account_name" {
  description = "Human-readable account name used in tags (e.g. 'Audit')"
  type        = string
  default     = "Aggregator"
}

# ── Network-hub remote state inputs ──────────────────────────────────────────

variable "network_hub_state_bucket" {
  description = "S3 bucket containing the network-hub Terraform state"
  type        = string
  default     = "terraform-network-hub-082787299790"
}

variable "network_hub_state_key" {
  description = "S3 key for the network-hub Terraform state object"
  type        = string
  default     = "terraform-network-hub.tfstate"
}

variable "network_hub_state_region" {
  description = "AWS region for the network-hub Terraform state bucket"
  type        = string
  default     = "us-east-1"
}

# ── Spoke VPC ─────────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block for the spoke VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "vpc_name" {
  description = "Name tag for the VPC and its resources"
  type        = string
  default     = "aggregator-spoke-vpc"
}

variable "tgw_subnet_cidrs" {
  description = "CIDR blocks for the two TGW attachment subnets (one per AZ)"
  type        = list(string)
  default     = ["10.1.0.0/28", "10.1.0.16/28"]
  validation {
    condition     = length(var.tgw_subnet_cidrs) == 2
    error_message = "Exactly two TGW subnet CIDRs must be provided for HA across two AZs."
  }
}

variable "tgw_subnet_azs" {
  description = "Availability zones for the two TGW attachment subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
  validation {
    condition     = length(var.tgw_subnet_azs) == 2
    error_message = "Exactly two AZs must be provided."
  }
}

# ── TGW Attachment ────────────────────────────────────────────────────────────

variable "destination_cidrs" {
  description = "CIDR blocks to route from the spoke toward TGW (e.g. RFC-1918 supernets)"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
}

variable "attachment_name" {
  description = "Name tag for the TGW VPC attachment"
  type        = string
  default     = "aggregator-to-hub-tgw"
}

# ── App-tier subnets ─────────────────────────────────────────────────────────

variable "app_subnet_cidrs" {
  description = "CIDR blocks for the two app-tier subnets (one per AZ)"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
  validation {
    condition     = length(var.app_subnet_cidrs) == 2
    error_message = "Exactly two app subnet CIDRs must be provided for HA across two AZs."
  }
}
