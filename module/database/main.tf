# RDS Subnet Group
resource "aws_db_subnet_group" "pmo_db_subnet_group" {
  name        = "${var.name}-db_subnet"
  subnet_ids  = [var.pri_sub_1, var.pri_sub_2]
  description = "Subnet group for Multi-AZ RDS deployment"

  tags = {
    Name = "${var.name}-db-Subnet-Group"
  }
}

data "vault_generic_secret" "vault_secret" {
  path = "secret/database"
}

resource "aws_db_instance" "pmo_mysql_database" {
  identifier             = "${var.name}-db"
  db_subnet_group_name   = aws_db_subnet_group.pmo_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_name                = "petclinic"

  # High Availability
  multi_az = false

  # Engine Settings
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  parameter_group_name = "default.mysql5.7"

  # Storage
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  # Credentials (from Vault)
  username = data.vault_generic_secret.vault_secret.data["username"]
  password = data.vault_generic_secret.vault_secret.data["password"]

  # Backup & Maintenance
  skip_final_snapshot = true

  # Security
  publicly_accessible = false
  deletion_protection = false
}

# RDS security group
resource "aws_security_group" "rds_sg" {
  name        = "${var.name}-rds-sg"
  description = "RDS Security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "mysqlport"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.bastion_sg, var.stage_sg, var.prod_sg]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-rds-sg"
  }
}
