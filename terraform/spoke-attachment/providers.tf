provider "aws" {
  alias   = "hub"
  region  = var.region
  profile = var.hub_profile

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = var.environment
      Stack       = "spoke-attachment"
      Scope       = "hub"
    }
  }
}

provider "aws" {
  alias   = "spoke"
  region  = var.region
  profile = var.spoke_profile

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = var.environment
      Stack       = "spoke-attachment"
      Scope       = "spoke"
    }
  }
}
