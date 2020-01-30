resource "aws_security_group" "default" {
  name   = "${var.name}-sg-default-${var.environment}"
  vpc_id = var.vpc_id

  ingress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol         = "-1"
    from_port        = 0
    to_port          = 0
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.name}-sg-default-${var.environment}"
    Environment = var.environment
  }
}

output "default" {
  value = aws_security_group.default
}