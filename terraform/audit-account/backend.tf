terraform {
  backend "s3" {
    bucket       = "terraform-network-hub-082787299790"
    key          = "terraform-audit-account.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
