variable "name" {}
variable "vpc" {}
variable "subnets" {
  type        = list(string)
  description = "List of subnet IDs for the bastion ASG"
}

variable "privatekey" {}
variable "nr_key" {}
variable "nr_acct_id" {}
variable "keypair" {}
variable "region" {
  default = "eu-west-1"
}