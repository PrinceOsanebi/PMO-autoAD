provider "aws" {
  region  = "eu-west-1"
  # profile = "pmo-admin"
}

terraform {
  backend "s3" {
    bucket       = "pmo-remote-state"
    use_lockfile = true
    key          = "infrastructure/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    # profile      = "pmo-admin"
  }
}

provider "vault" {
  address = "https://vault.pmolabs.space"
  token   = "REMOVED_SECRET"
}
