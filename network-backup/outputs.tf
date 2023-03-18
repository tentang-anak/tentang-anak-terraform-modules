output "vpc_id" {
  description = "The ID of the VPC"
  value       = concat(aws_vpc.this.*.id, [""])[0]
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = concat(aws_vpc.this.*.cidr_block, [""])[0]
}

output "vpc_owner_id" {
  description = "The ID of the AWS account that owns the VPC"
  value       = concat(aws_vpc.this.*.owner_id, [""])[0]
}

output "subnets_private" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private.*.id
}

output "subnets_public" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public.*.id
}
