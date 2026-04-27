provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = "production"
      AccountName = "Network-hub"
      AccountId   = "082787299790"
    }
  }
}
