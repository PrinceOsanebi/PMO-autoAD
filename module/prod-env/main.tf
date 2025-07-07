# PROD environment Security Group for EC2 instances
resource "aws_security_group" "prod_sg" {
  name        = "${var.name}-prod-sg"
  description = "Prod environment security group for EC2 instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow SSH access from bastion and ansible for management"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion, var.ansible]
  }

  ingress {
    description     = "Allow HTTP traffic from ALB on port 8080"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.prod-elb-sg.id]
  }

  ingress {
    description     = "Allow HTTP traffic from ALB on port 8081"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.prod-elb-sg.id]
  }

  egress {
    description = "Allow all outbound traffic from prod instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-prod-sg"
    Environment = "prod"
  }
}

# RedHat AMI Data Source
data "aws_ami" "redhat" {
  most_recent = true
  owners      = ["309956199498"]

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

# Launch Template for Prod
resource "aws_launch_template" "prod_lnch_tmpl" {
  image_id      = data.aws_ami.redhat.id
  name_prefix   = "${var.name}-prod-web-tmpl"
  instance_type = "t2.medium"
  key_name      = var.key_name

  # user_data = base64encode(templatefile("./module/prod-env/docker-script.sh", {
  #   nexus_ip   = var.nexus_ip,
  #   nr_key     = var.nr_key,
  #   nr_acct_id = var.nr_acct_id,
  #   port       = var.port
  # }))

  network_interfaces {
    security_groups = [aws_security_group.prod_sg.id]
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name        = "${var.name}-prod-web-instance"
    Environment = "prod"
  }
}

# Auto Scaling Group for Prod
resource "aws_autoscaling_group" "prod_autoscaling_grp" {
  name                      = "${var.name}-prod-asg"
  max_size                  = 3
  min_size                  = 1
  desired_capacity          = 1
  health_check_grace_period = 120
  health_check_type         = "EC2"
  force_delete              = true

  launch_template {
    id      = aws_launch_template.prod_lnch_tmpl.id
    version = "$Latest"
  }

  vpc_zone_identifier = [var.pri_subnet1, var.pri_subnet2]

  target_group_arns = [
    aws_lb_target_group.prod-target-group.arn,
    aws_lb_target_group.prod-target-group-8081.arn
  ]

  tag {
    key                 = "Name"
    value               = "${var.name}-prod-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "prod"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy
resource "aws_autoscaling_policy" "prod-asg-policy" {
  name                   = "asg-policy"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.prod_autoscaling_grp.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Load Balancer for Prod
resource "aws_lb" "prod_LB" {
  name               = "${var.name}-prod-LB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.prod-elb-sg.id]
  subnets            = [var.pub_subnet1, var.pub_subnet2]

  tags = {
    Name = "${var.name}-prod-LB"
  }
}

# Security Group for ELB
resource "aws_security_group" "prod-elb-sg" {
  name        = "${var.name}-prod-elb-sg"
  description = "Prod ELB Security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTPS (443) traffic from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-prod-elb-sg"
    Environment = "prod"
  }
}

# Target Group for port 8080
resource "aws_lb_target_group" "prod-target-group" {
  name        = "${var.name}-prod-tg-8080"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
    path                = "/"
  }

  tags = {
    Name = "${var.name}-prod-tg-8080"
  }
}

# Target Group for port 8081
resource "aws_lb_target_group" "prod-target-group-8081" {
  name        = "${var.name}-prod-tg-8081"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 5
    path                = "/"
  }

  tags = {
    Name        = "${var.name}-prod-tg-8081"
    Environment = "prod"
  }
}

# HTTP Listener
resource "aws_lb_listener" "prod_load_balancer_listener_http" {
  load_balancer_arn = aws_lb.prod_LB.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod-target-group.arn
  }
}

# HTTPS Listener
resource "aws_lb_listener" "prod_load_balancer_listener_https" {
  load_balancer_arn = aws_lb.prod_LB.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod-target-group.arn
  }
}

# Listener Rule for /swap to port 8081
resource "aws_lb_listener_rule" "prod_listener_rule_8081" {
  listener_arn = aws_lb_listener.prod_load_balancer_listener_http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod-target-group-8081.arn
  }

  condition {
    path_pattern {
      values = ["/swap*"]
    }
  }
}

# Route 53 Zone
data "aws_route53_zone" "pmo-acp-zone" {
  name         = var.domain
  private_zone = false
}

# Route 53 A Record
resource "aws_route53_record" "prod-record" {
  zone_id = data.aws_route53_zone.pmo-acp-zone.zone_id
  name    = "prod.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.prod_LB.dns_name
    zone_id                = aws_lb.prod_LB.zone_id
    evaluate_target_health = true
  }
}
