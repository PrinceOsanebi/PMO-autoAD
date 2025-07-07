locals {
  name = "pmo"
}

data "aws_route53_zone" "zone" {
  name         = var.domain_name
  private_zone = false
}

data "aws_acm_certificate" "cert" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
  types       = ["AMAZON_ISSUED"]
}
module "vpc" {
  source = "./module/vpc"
  name   = local.name
  az1    = "eu-west-1a"
  az2    = "eu-west-1b"
}

module "bastion" {
  source     = "./module/bastion"
  name       = local.name
  vpc        = module.vpc.vpc_id
  subnets    = [module.vpc.pub_sub1_id, module.vpc.pub_sub2_id]
  keypair    = module.vpc.public_key
  privatekey = module.vpc.private_key
  nr_acct_id = var.nr_acct_id
  nr_key     = var.nr_key
}

module "ansible" {
  source      = "./module/ansible"
  name        = local.name
  keypair     = module.vpc.public_key
  subnet_id   = module.vpc.pri_sub1_id
  vpc         = module.vpc.vpc_id
  bastion_key = module.bastion.bastion_sg
  private_key = module.vpc.private_key
  nexus_ip    = module.nexus.nexus_ip
  nr_key      = var.nr_key
  nr_acct_id  = var.nr_acct_id
}

module "database" {
  source     = "./module/database"
  pri_sub_1  = module.vpc.pri_sub1_id
  pri_sub_2  = module.vpc.pri_sub2_id
  bastion_sg = module.bastion.bastion_sg
  vpc_id     = module.vpc.vpc_id
  stage_sg   = module.stage-env.stage_sg
  prod_sg    = module.prod-env.prod_sg
  name       = local.name
}

module "sonarqube" {
  source         = "./module/sonarqube"
  name           = local.name
  vpc            = module.vpc.vpc_id
  vpc_cidr_block = "10.0.0.0/16"
  keypair        = module.vpc.public_key
  subnet_id      = module.vpc.pub_sub1_id
  subnets        = module.vpc.pub_sub1_id
  certificate    = data.aws_acm_certificate.cert.arn
  hosted_zone_id = data.aws_route53_zone.zone.id
  domain_name    = var.domain_name
}

module "prod-env" {
  source       = "./module/prod-env"
  name         = local.name
  vpc_id       = module.vpc.vpc_id
  bastion      = module.bastion.bastion_sg
  key_name     = module.vpc.public_key
  pri_subnet1  = module.vpc.pri_sub1_id
  pri_subnet2  = module.vpc.pri_sub2_id
  pub_subnet1  = module.vpc.pub_sub1_id
  pub_subnet2  = module.vpc.pub_sub2_id
  acm_cert_arn = data.aws_acm_certificate.cert.arn
  domain       = var.domain_name
  nexus_ip     = module.nexus.nexus_ip
  nr_key       = var.nr_key
  nr_acct_id   = var.nr_acct_id
  ansible      = module.ansible.ansible_sg
  port         = var.port
}

module "stage-env" {
  source       = "./module/stage-env"
  name         = local.name
  vpc_id       = module.vpc.vpc_id
  bastion      = module.bastion.bastion_sg
  key_name     = module.vpc.public_key
  pri_subnet1  = module.vpc.pri_sub1_id
  pri_subnet2  = module.vpc.pri_sub2_id
  pub_subnet1  = module.vpc.pub_sub1_id
  pub_subnet2  = module.vpc.pub_sub2_id
  acm_cert_arn = data.aws_acm_certificate.cert.arn
  domain       = var.domain_name
  nexus_ip     = module.nexus.nexus_ip
  nr_key       = var.nr_key
  nr_acct_id   = var.nr_acct_id
  ansible      = module.ansible.ansible_sg
  port         = var.port
}

module "nexus" {
  source         = "./module/nexus"
  name           = local.name
  vpc            = module.vpc.vpc_id
  keypair        = module.vpc.public_key
  subnet_id      = module.vpc.pub_sub1_id
  subnets        = module.vpc.pub_sub1_id
  certificate    = data.aws_acm_certificate.cert.arn
  hosted_zone_id = data.aws_route53_zone.zone.id
  domain_name    = var.domain_name
}
