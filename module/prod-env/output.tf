output "prod_sg" {
  description = "Prod environment security group ID"
  value       = aws_security_group.prod_sg.id
}

