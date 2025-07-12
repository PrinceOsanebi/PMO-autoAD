# Fetch the latest RedHat RHEL 9 AMI
data "aws_ami" "redhat" {
  most_recent = true
  owners      = ["309956199498"] # RedHat's official AWS account

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

# Create IAM role for Ansible EC2 to assume
resource "aws_iam_role" "ansible-role" {
  name = "ansible-discovery-role"

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

# Attach EC2 full access policy to Ansible IAM role
resource "aws_iam_role_policy_attachment" "ec2-policy" {
  role       = aws_iam_role.ansible-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# Attach S3 full access policy to Ansible IAM role
resource "aws_iam_role_policy_attachment" "s3-policy" {
  role       = aws_iam_role.ansible-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# Create IAM instance profile for Ansible EC2
resource "aws_iam_instance_profile" "ansible-profile" {
  name = "ansible-discovery-profile"
  role = aws_iam_role.ansible-role.name
}

# Create security group for Ansible EC2 instance
resource "aws_security_group" "ansible-sg" {
  name        = "${var.name}ansible-sg"
  description = "Allow SSH access for Ansible EC2"
  vpc_id      = var.vpc

  ingress {
    description     = "Allow SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_key]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-ansible-sg"
  }
}

# Launch Ansible EC2 instance
resource "aws_instance" "ansible-server" {
  ami                    = data.aws_ami.redhat.id
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.ansible-profile.name
  vpc_security_group_ids = [aws_security_group.ansible-sg.id]
  key_name               = var.keypair
  subnet_id              = var.subnet_id
  user_data              = local.ansible_userdata
  monitoring             = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "${var.name}-ansible-server"
  }
}

# Upload Ansible scripts to S3 from local path
resource "null_resource" "ansible-setup" {
  provisioner "local-exec" {
    command = "aws s3 cp --recursive ${path.module}/script/ s3://pmo-remote-state/ansible-script/"
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}
