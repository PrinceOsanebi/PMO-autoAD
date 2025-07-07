variable "keypair" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
}

variable "name" {
  description = "Base name prefix for resources"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where the EC2 instance will be launched"
  type        = string
}

variable "vpc" {
  description = "VPC ID where security groups and EC2 instances are created"
  type        = string
}

variable "bastion_key" {
  description = "Security Group ID of the bastion host allowed to SSH to Ansible server"
  type        = string
}

variable "private_key" {
  description = "Private key for instance"
  type        = string
  sensitive   = true
}

variable "nexus_ip" {
  description = "IP address"
  type        = string
}

variable "nr_key" {
  description = "New relic"
  type        = string
}

variable "nr_acct_id" {
  description = "Account ID for new relic"
  type        = string
}
