variable "vpc_name" {}


# Create a VPC
resource "aws_vpc" "test" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
  "Name" = var.vpc_name
  }
}

output "vpc_id" {
value = aws_vpc.test.id
}
