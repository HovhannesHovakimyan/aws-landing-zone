provider "aws" {
  alias   = "hub"
  region  = var.region
  profile = var.hub_profile != null && trimspace(var.hub_profile) != "" ? var.hub_profile : null

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = var.environment
      Stack       = "audit-account"
      Scope       = "hub"
    }
  }
}

provider "aws" {
  alias   = "spoke"
  region  = var.region
  profile = var.spoke_profile != null && trimspace(var.spoke_profile) != "" ? var.spoke_profile : null

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = var.environment
      Stack       = "audit-account"
      AccountName = var.account_name
      Scope       = "spoke"
    }
  }
}
