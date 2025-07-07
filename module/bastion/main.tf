# Creating Baston Host Security group 
resource "aws_security_group" "bastion_sg" {
  name        = "${var.name}-baston-sg"
  description = "Allow only outbound traffic"
  vpc_id      = var.vpc
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.name}-baston-sg"
  }
}

# Create IAM role for SSM
resource "aws_iam_role" "ssm-role" {
  name = "bastion-ssm-role"
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

# Attach the SSM policy to the role
resource "aws_iam_role_policy_attachment" "ssm-policy" {
  role       = aws_iam_role.ssm-role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# create IAM instance profile
resource "aws_iam_instance_profile" "ssm-profile" {
  name = "bastion-ssm-profile"
  role = aws_iam_role.ssm-role.name
}

# Data source to get the latest Ubuntu AMI
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

# Create Launch Template for Bastion Host
resource "aws_launch_template" "bastion-lt" {
  name_prefix   = "${var.name}-bastion-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = var.keypair
  iam_instance_profile {
    name = aws_iam_instance_profile.ssm-profile.name
  }
  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.bastion_sg.id]
  }
  # user_data = base64encode(templatefile("./module/bastion/userdata.sh", {
  #   privatekey = var.privatekey,
  #   nr_key     = var.nr_key,
  #   nr_acct_id = var.nr_acct_id,
  #   region     = var.region
  # }))

  tags = {
    Name = "${var.name}-bastion"
  }
}

resource "aws_autoscaling_group" "bastion-asg" {
  name                      = "${var.name}-bastion-asg"
  max_size                  = 3
  min_size                  = 1
  desired_capacity          = 1
  health_check_grace_period = 120
  health_check_type         = "EC2"
  force_delete              = true
  launch_template {
    id      = aws_launch_template.bastion-lt.id
    version = "$Latest"
  }
  vpc_zone_identifier = var.subnets

  tag {
    key                 = "Name"
    value               = "${var.name}-bastion-asg"
    propagate_at_launch = true
  }
}

# Creat ASG policy for Baston Host
resource "aws_autoscaling_policy" "bastion-asg-policy" {
  name                   = "${var.name}-bastion-asg-policy"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.bastion-asg.name
  policy_type            = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}