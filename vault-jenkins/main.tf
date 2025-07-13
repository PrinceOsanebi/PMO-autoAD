locals {
  name = "vault-jenkins" # Project-specific name prefix
}

# Create a new VPC
resource "aws_vpc" "vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  tags = {
    Name = "${local.name}-vpc"
  }
}

# Create a public subnet in availability zone eu-west-1a
resource "aws_subnet" "pub_sub" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1a"
  tags = {
    Name = "${local.name}-pub_sub"
  }
}

# Create an Internet Gateway for the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${local.name}-igw"
  }
}

# Create a route table for the public subnet
resource "aws_route_table" "pub_rt" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${local.name}-pub_rt"
  }
}

# Associate the public subnet with the public route table
resource "aws_route_table_association" "ass-public_subnet" {
  subnet_id      = aws_subnet.pub_sub.id
  route_table_id = aws_route_table.pub_rt.id
}

# Generate an RSA private key
resource "tls_private_key" "keypair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save the private key to a local PEM file
resource "local_file" "private_key" {
  content         = tls_private_key.keypair.private_key_pem
  filename        = "${local.name}-key.pem"
  file_permission = "400"
}

# Create an AWS key pair using the generated public key
resource "aws_key_pair" "public_key" {
  key_name   = "${local.name}-key"
  public_key = tls_private_key.keypair.public_key_openssh
}

# Fetch the most recent RHEL 9 AMI (HVM, x86_64) from RedHat
data "aws_ami" "redhat" {
  most_recent = true
  owners      = ["309956199498"] # RedHat's AWS account ID
  filter {
    name   = "name"
    values = ["RHEL-9*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Create IAM role for Jenkins server to assume SSM role
resource "aws_iam_role" "ssm-jenkins-role" {
  name = "${local.name}-ssm-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Attach AmazonSSMManagedInstanceCore policy to the Jenkins IAM role
resource "aws_iam_role_policy_attachment" "jenkins_ssm_managed_instance_core" {
  role       = aws_iam_role.ssm-jenkins-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach AdministratorAccess policy to the Jenkins IAM role
resource "aws_iam_role_policy_attachment" "jenkins-admin-role-attachment" {
  role       = aws_iam_role.ssm-jenkins-role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create IAM instance profile for Jenkins EC2 instance
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "${local.name}-ssm-jenkins-profile"
  role = aws_iam_role.ssm-jenkins-role.name
}

# Create security group for Jenkins server (allowing port 8080 from anywhere)
resource "aws_security_group" "jenkins_sg" {
  name        = "${local.name}-jenkins-sg"
  description = "Allow SSH and HTTPS"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-jenkins-sg"
  }
}

# Launch Jenkins EC2 instance with RedHat AMI
resource "aws_instance" "jenkins-server" {
  ami                         = data.aws_ami.redhat.id # Use latest RedHat AMI
  instance_type               = "t3.medium"
  key_name                    = aws_key_pair.public_key.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.pub_sub.id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ssm_instance_profile.name

  root_block_device {
    volume_size = 20    # Root volume size in GB
    volume_type = "gp3" # Use gp3 SSD
    encrypted   = true  # Encrypt the root volume
  }

  user_data = templatefile("./jenkins_userdata.sh", {
    region = var.region
  })

  metadata_options {
    http_tokens = "required" # Enforce IMDSv2 for security
  }

  tags = {
    Name = "${local.name}-jenkins-server"
  }
}
# Create ACM certificate with DNS validation for the primary domain and wildcard subdomain
resource "aws_acm_certificate" "acm-cert" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true # Prevent downtime during replacement
  }

  tags = {
    Name = "${local.name}-acm-cert"
  }
}

# Fetch Route53 hosted zone information for the domain
data "aws_route53_zone" "pmo-acp-zone" {
  name         = var.domain
  private_zone = false
}

# Create DNS validation records in Route53 for ACM certificate
resource "aws_route53_record" "acm_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.acm-cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.pmo-acp-zone.zone_id
  allow_overwrite = true
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]

  depends_on = [aws_acm_certificate.acm-cert] # Ensure domain_validation_options are available
}

# Validate the ACM certificate after DNS records are created
resource "aws_acm_certificate_validation" "pmo_cert_validation" {
  certificate_arn         = aws_acm_certificate.acm-cert.arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation_record : record.fqdn]

  depends_on = [aws_route53_record.acm_validation_record]
}

# Create security group for Jenkins ELB to allow HTTPS traffic
resource "aws_security_group" "jenkins_elb_sg" {
  name        = "${local.name}-jenkins-elb-sg"
  description = "Allow HTTPS"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-jenkins-elb-sg"
  }
}

# Create Classic Load Balancer (ELB) for Jenkins with SSL termination
resource "aws_elb" "elb_jenkins" {
  depends_on      = [aws_acm_certificate_validation.pmo_cert_validation]
  name            = "elb-jenkins"
  security_groups = [aws_security_group.jenkins_elb_sg.id]
  subnets         = [aws_subnet.pub_sub.id]

  listener {
    instance_port      = 8080
    instance_protocol  = "HTTP"
    lb_port            = 443
    lb_protocol        = "HTTPS"
    ssl_certificate_id = aws_acm_certificate.acm-cert.arn
  }


  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
    target              = "TCP:8080"
  }

  instances                   = [aws_instance.jenkins-server.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "${local.name}-jenkins-elb"
  }
}

# Get the latest Ubuntu 22.04 LTS AMI (Jammy) from Canonical
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create an EC2 instance to run HashiCorp Vault
resource "aws_instance" "vault" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.medium"
  key_name                    = aws_key_pair.public_key.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.pub_sub.id
  vpc_security_group_ids      = [aws_security_group.vault_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.vault_ssm_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  # User data script to install Jenkins and required tools
  user_data = templatefile("./vault.sh", {
    region        = var.region,
    VAULT_VERSION = "1.18.3",
    key           = aws_kms_key.vault.id
  })

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${local.name}-vault-server"
  }
}

resource "time_sleep" "wait_3_min" {
  depends_on      = [aws_instance.vault]
  create_duration = "300s"
}

resource "null_resource" "fetch_token_ssm" {
  depends_on = [aws_instance.vault, time_sleep.wait_3_min]

  provisioner "local-exec" {
    interpreter = ["C:/Program Files/Git/bin/bash.exe", "-c"]
    command     = <<EOT
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --comment "Fetch Vault token" \
  --instance-ids ${aws_instance.vault.id} \
  --region "eu-west-1" \
  --parameters 'commands=["cat /home/ubuntu/token.txt"]' \
  --query "Command.CommandId" \
  --output text \
  --profile "pmo-admin" > command_id.txt

sleep 5

aws ssm get-command-invocation \
  --command-id $(cat command_id.txt) \
  --instance-id ${aws_instance.vault.id} \
  --region "eu-west-1" \
  --query "StandardOutputContent" \
  --output text \
  --profile "pmo-admin" > token.txt

rm -f command_id.txt
EOT
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "del token.txt"
    interpreter = ["PowerShell", "-Command"]
  }
}

# Create security group for Vault (allow port 8200)
resource "aws_security_group" "vault_sg" {
  name        = "${local.name}-vault-sg"
  description = "Allow Vault traffic"
  vpc_id      = aws_vpc.vpc.id

  # Inbound: HTTP on port 80
  ingress {
    from_port   = 8200
    to_port     = 8200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: Allow all traffic (to EC2)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-vault-sg"
  }
}

# Create a KMS key to encrypt Vault unseal keys
resource "aws_kms_key" "vault" {
  description             = "Vault KMS key for unsealing and secrets encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 20

  tags = {
    Name = "${local.name}-vault-kms-key"
  }
}

# Create and attach an IAM role with SSM permissions to the Vault instance
resource "aws_iam_role" "vault_ssm_role" {
  name = "${local.name}-ssm-vault-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

# Create IAM role policy to give permissions to the KMS key
resource "aws_iam_role_policy" "kms_policy" {
  name = "${local.name}-kms-policy"
  role = aws_iam_role.vault_ssm_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ],
        Resource = aws_kms_key.vault.arn
      }
    ]
  })
}

# Create instance profile for Vault
resource "aws_iam_instance_profile" "vault_ssm_profile" {
  name = "${local.name}-ssm-vault-instance-profile"
  role = aws_iam_role.vault_ssm_role.name
}

# Attach the AmazonSSMManagedInstanceCore policy to allow SSM functionality
resource "aws_iam_role_policy_attachment" "vault_ssm_attachment" {
  role       = aws_iam_role.vault_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Security Group for Vault ELB to allow HTTPS traffic
resource "aws_security_group" "vault_elb_sg" {
  name        = "${local.name}-vault-elb-sg"
  description = "Allow HTTPS traffic to Vault ELB"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-vault-elb-sg"
  }
}

# Create a new load balancer for Vault
resource "aws_elb" "vault_elb" {
  depends_on      = [aws_acm_certificate_validation.pmo_cert_validation]
  name            = "${local.name}-vault-elb"
  subnets         = [aws_subnet.pub_sub.id]
  security_groups = [aws_security_group.vault_elb_sg.id]

  listener {
    instance_port      = 8200
    instance_protocol  = "HTTP"
    lb_port            = 443
    lb_protocol        = "HTTPS"
    ssl_certificate_id = aws_acm_certificate.acm-cert.arn
  }

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    target              = "TCP:8200"
  }


  instances                   = [aws_instance.vault.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags = {
    Name = "${local.name}-vault-elb"
  }
}

# Create Route 53 record for Vault server
resource "aws_route53_record" "vault_record" {
  zone_id = data.aws_route53_zone.pmo-acp-zone.zone_id
  name    = "vault.${var.domain}"
  type    = "A"
  alias {
    name                   = aws_elb.vault_elb.dns_name
    zone_id                = aws_elb.vault_elb.zone_id
    evaluate_target_health = true
  }
}

# Create Route 53 record for Jenkins server
resource "aws_route53_record" "jenkins_record" {
  zone_id = data.aws_route53_zone.pmo-acp-zone.zone_id
  name    = "jenkins.${var.domain}"
  type    = "A"
  alias {
    name                   = aws_elb.elb_jenkins.dns_name
    zone_id                = aws_elb.elb_jenkins.zone_id
    evaluate_target_health = true
  }
}
