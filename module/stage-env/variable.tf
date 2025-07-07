variable "name" {}

variable "vpc_id" {}

variable "bastion" {}

variable "key_name" {}

variable "pri_subnet1" {}

variable "pri_subnet2" {}

variable "pub_subnet1" {}

variable "pub_subnet2" {}

variable "acm_cert_arn" {}

variable "domain" {}

variable "nexus_ip" {}

variable "nr_key" {}

variable "nr_acct_id" {}

variable "ansible" {}

variable "port" {
  type        = number
  default     = 8080
  description = "Primary container port, the script will swap between this and the other port (8080 or 8081)"
}




