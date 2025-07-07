provider "aws" {
  region  = var.region
  profile = "pmo-admin"
}

terraform {
  backend "s3" {
    bucket       = "pmo-remote-state"
    use_lockfile = true
    key          = "vault-jenkins/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    profile      = "pmo-admin"
  }
}