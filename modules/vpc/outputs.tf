output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet ids, ordered by AZ."
  value       = [for az in var.availability_zones : aws_subnet.public[az].id]
}

output "private_subnet_ids" {
  description = "List of private subnet ids, ordered by AZ."
  value       = [for az in var.availability_zones : aws_subnet.private[az].id]
}

output "public_subnet_ids_by_az" {
  description = "Map of AZ name to public subnet id."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids_by_az" {
  description = "Map of AZ name to private subnet id."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "internet_gateway_id" {
  description = "IGW id (useful for additional routes outside the module)."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "List of NAT gateway ids actually created (1 if single_nat_gateway, otherwise len(azs))."
  value       = [for ng in aws_nat_gateway.this : ng.id]
}

output "availability_zones" {
  description = "AZs the module is deployed in (echoed back for downstream modules)."
  value       = var.availability_zones
}
