variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-west-1"
}

variable "nr_key" {
  default = "NRAK-4FNJBSGOTULJ4XCZW4P2JOMPOKY11" # to be updated
}
variable "nr_acct_id" {
  default = 649634211 # to be updated
}

variable "domain_name" {
  default = "pmolabs.space"
}

variable "port" {
  type        = number
  default     = 8080
  description = "Primary container port, toggles with the alternate port (8080 or 8081)."
}

variable "vault_token" {
  description = "hvs.fBv6TGqAdwnAP0pebq1Cu9GA"
  type        = string
  sensitive   = true
}



