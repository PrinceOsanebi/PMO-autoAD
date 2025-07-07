# Stage environment Security Group for EC2 instances
resource "aws_security_group" "stage_sg" {
  name        = "${var.name}-stage-sg"
  description = "Stage environment security group for EC2 instances"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow SSH access from bastion and ansible for management"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion, var.ansible]
  }

  ingress {
    description     = "Allow HTTP traffic from ALB on port 8080 for primary app container: swap/alternate deployment"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.stage-elb-sg.id]
  }

  ingress {
    description     = "Allow HTTP traffic from ALB on port 8081 for secondary app container: swap/alternate deployment"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.stage-elb-sg.id]
  }

  egress {
    description = "Allow all outbound traffic from stage instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-stage-sg"
    Environment = "stage"
  }
}

# Data source to get latest RedHat AMI for instances
data "aws_ami" "redhat" {
  most_recent = true
  owners      = ["309956199498"] # RedHat's owner ID

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

# Create Launch Template for Stage EC2 Instances with docker startup script
resource "aws_launch_template" "stage_lnch_tmpl" {
  image_id      = data.aws_ami.redhat.id
  name_prefix   = "${var.name}-stage-web-tmpl"
  instance_type = "t2.medium"
  key_name      = var.key_name

  # user_data = base64encode(templatefile("./module/stage-env/docker-script.sh", {
  #   nexus_ip   = var.nexus_ip,
  #   nr_key     = var.nr_key,
  #   nr_acct_id = var.nr_acct_id,
  #   port       = var.port
  # }))

  network_interfaces {
    security_groups = [aws_security_group.stage_sg.id]
  }

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name        = "${var.name}-stage-web-instance"
    Environment = "stage"
  }
}

# Create Auto Scaling Group for Stage Environment
resource "aws_autoscaling_group" "stage_autoscaling_grp" {
  name                      = "${var.name}-stage-asg"
  max_size                  = 3
  min_size                  = 1
  desired_capacity          = 1
  health_check_grace_period = 120
  health_check_type         = "EC2"
  force_delete              = true

  launch_template {
    id      = aws_launch_template.stage_lnch_tmpl.id
    version = "$Latest"
  }

  vpc_zone_identifier = [var.pri_subnet1, var.pri_subnet2]

  target_group_arns = [
    aws_lb_target_group.stage-target-group.arn,     # Primary container port 8080
    aws_lb_target_group.stage-target-group-8081.arn # Secondary container port 8081
  ]

  tag {
    key                 = "Name"
    value               = "${var.name}-stage-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "stage"
    propagate_at_launch = true
  }
}

# Create autoscaling group policy for CPU Utilization-based scaling
resource "aws_autoscaling_policy" "stage-asg-policy" {
  name                   = "asg-policy"
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.stage_autoscaling_grp.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# Create Application Load Balancer for stage Environment
resource "aws_lb" "stage_LB" {
  name               = "${var.name}-stage-LB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.stage-elb-sg.id]
  subnets            = [var.pub_subnet1, var.pub_subnet2]

  tags = {
    Name = "${var.name}-stage-LB"
  }
}

# Stage ELB security group
resource "aws_security_group" "stage-elb-sg" {
  name        = "${var.name}-stage-elb-sg"
  description = "Stage ELB Security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTPS (443) traffic from anywhere to the ELB"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic from ELB"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.name}-stage-elb-sg"
    Environment = "stage"
  }
}

# Create Target Group for primary container port 8080
resource "aws_lb_target_group" "stage-target-group" {
  name        = "${var.name}-stage-tg-8080"
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
    Name = "${var.name}-stage-tg-8080"
  }
}

# Create Target Group for secondary container port 8081 (swap/alternate container deployment)
resource "aws_lb_target_group" "stage-target-group-8081" {
  name        = "${var.name}-stage-tg-8081"
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
    Name        = "${var.name}-stage-tg-8081"
    Environment = "stage"
  }
}

# Create HTTP Listener for Stage ALB forwarding to primary container target group (8080)
resource "aws_lb_listener" "stage_load_balancer_listener_http" {
  load_balancer_arn = aws_lb.stage_LB.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stage-target-group.arn
  }
}

# Create HTTPS Listener for Stage ALB forwarding to primary container target group (8080)
resource "aws_lb_listener" "stage_load_balancer_listener_https" {
  load_balancer_arn = aws_lb.stage_LB.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.acm_cert_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stage-target-group.arn
  }
}

# Add listener rule to route /swap requests to secondary container on port 8081 (blue-green deployment)
resource "aws_lb_listener_rule" "stage_listener_rule_8081" {
  listener_arn = aws_lb_listener.stage_load_balancer_listener_http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stage-target-group-8081.arn
  }

  condition {
    path_pattern {
      values = ["/swap*"]
    }
  }
}

# Data source for Route 53 zone for the domain
data "aws_route53_zone" "pmo-acp-zone" {
  name         = var.domain
  private_zone = false
}

# Create Route 53 A record for stage environment pointing to ALB
resource "aws_route53_record" "stage-record" {
  zone_id = data.aws_route53_zone.pmo-acp-zone.zone_id
  name    = "stage.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.stage_LB.dns_name
    zone_id                = aws_lb.stage_LB.zone_id
    evaluate_target_health = true
  }
}
