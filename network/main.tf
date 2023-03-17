locals {
  max_subnet_length = max(
    length(var.private_subnets)
  )
  nat_gateway_count = var.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(var.azs) : local.max_subnet_length

  # Use `local.vpc_id` to give a hint to Terraform that subnets should be deleted before secondary CIDR blocks can be free!
  vpc_id = element(
    concat(
      aws_vpc_ipv4_cidr_block_association.this.*.vpc_id,
      aws_vpc.this.*.id,
      [""],
    ),
    0,
  )
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  count = var.create_vpc ? 1 : 0

  cidr_block                       = var.cidr
  instance_tenancy                 = var.instance_tenancy
  enable_dns_hostnames             = var.enable_dns_hostnames
  enable_dns_support               = var.enable_dns_support
  enable_classiclink               = var.enable_classiclink
  enable_classiclink_dns_support   = var.enable_classiclink_dns_support
  assign_generated_ipv6_cidr_block = var.enable_ipv6

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.vpc_tags,
  )
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  count = var.create_vpc && length(var.secondary_cidr_blocks) > 0 ? length(var.secondary_cidr_blocks) : 0

  vpc_id = aws_vpc.this[0].id

  cidr_block = element(var.secondary_cidr_blocks, count.index)
}

resource "aws_default_security_group" "this" {
  count = var.create_vpc && var.manage_default_security_group ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  dynamic "ingress" {
    for_each = var.default_security_group_ingress
    content {
      self             = lookup(ingress.value, "self", null)
      cidr_blocks      = compact(split(",", lookup(ingress.value, "cidr_blocks", "")))
      ipv6_cidr_blocks = compact(split(",", lookup(ingress.value, "ipv6_cidr_blocks", "")))
      prefix_list_ids  = compact(split(",", lookup(ingress.value, "prefix_list_ids", "")))
      security_groups  = compact(split(",", lookup(ingress.value, "security_groups", "")))
      description      = lookup(ingress.value, "description", null)
      from_port        = lookup(ingress.value, "from_port", 0)
      to_port          = lookup(ingress.value, "to_port", 0)
      protocol         = lookup(ingress.value, "protocol", "-1")
    }
  }

  dynamic "egress" {
    for_each = var.default_security_group_egress
    content {
      self             = lookup(egress.value, "self", null)
      cidr_blocks      = compact(split(",", lookup(egress.value, "cidr_blocks", "")))
      ipv6_cidr_blocks = compact(split(",", lookup(egress.value, "ipv6_cidr_blocks", "")))
      prefix_list_ids  = compact(split(",", lookup(egress.value, "prefix_list_ids", "")))
      security_groups  = compact(split(",", lookup(egress.value, "security_groups", "")))
      description      = lookup(egress.value, "description", null)
      from_port        = lookup(egress.value, "from_port", 0)
      to_port          = lookup(egress.value, "to_port", 0)
      protocol         = lookup(egress.value, "protocol", "-1")
    }
  }

  tags = merge(
    {
      "Name" = format("%s", var.default_security_group_name)
    },
    var.tags,
    var.default_security_group_tags,
  )
}

################################################################################
# DHCP Options Set
################################################################################

resource "aws_vpc_dhcp_options" "this" {
  count = var.create_vpc && var.enable_dhcp_options ? 1 : 0

  domain_name          = var.dhcp_options_domain_name
  domain_name_servers  = var.dhcp_options_domain_name_servers
  ntp_servers          = var.dhcp_options_ntp_servers
  netbios_name_servers = var.dhcp_options_netbios_name_servers
  netbios_node_type    = var.dhcp_options_netbios_node_type

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.dhcp_options_tags,
  )
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = var.create_vpc && var.enable_dhcp_options ? 1 : 0

  vpc_id          = local.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

################################################################################
# Subnet Private and Public
################################################################################

resource "aws_subnet" "private" {
  count = length(var.subnets_private) * length(var.subnets_private[0].azs)

  vpc_id            = local.vpc_id
  cidr_block        = var.subnets_private[floor(count.index / length(var.subnets_private[0].azs))].subnet_ip[count.index % length(var.subnets_private[0].azs)]
  availability_zone = var.subnets_private[floor(count.index / length(var.subnets_private[0].azs))].azs[count.index % length(var.subnets_private[0].azs)]
  tags = {
    Name = var.subnets_private[floor(count.index / length(var.subnets_private[0].azs))].subnet_name[count.index % length(var.subnets_private[0].azs)]
  }
}


resource "aws_subnet" "public" {
  count = length(var.subnets_public) * length(var.subnets_public[0].azs)

  vpc_id            = local.vpc_id
  map_public_ip_on_launch         = var.map_public_ip_on_launch
  cidr_block        = var.subnets_public[floor(count.index / length(var.subnets_public[0].azs))].subnet_ip[count.index % length(var.subnets_public[0].azs)]
  availability_zone = var.subnets_public[floor(count.index / length(var.subnets_public[0].azs))].azs[count.index % length(var.subnets_public[0].azs)]
  tags = {
    Name = var.subnets_public[floor(count.index / length(var.subnets_public[0].azs))].subnet_name[count.index % length(var.subnets_public[0].azs)]
  }
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  count = length(var.subnets_public) > 0 ? 1 : 0
  vpc_id            = local.vpc_id

  tags = merge(
    {
      "Name" = format("%s", var.name)
    },
    var.tags,
    var.igw_tags,
  )
}

################################################################################
# Publiс routes
################################################################################

resource "aws_route_table" "public" {
  count = length(var.subnets_public) > 0 ? 1 : 0

  vpc_id            = local.vpc_id

  propagating_vgws       = var.default_route_table_propagating_vgws

  tags = merge(
    {
      "Name" = format("%s-${var.public_subnet_suffix}", var.name)
    },
    var.tags,
    var.public_route_table_tags,
  )
}

resource "aws_route" "public_internet_gateway" {
  count = length(var.subnets_public) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_main_route_table_association" "a" {
  vpc_id            = local.vpc_id
  route_table_id    = aws_route_table.public[0].id
}

# NAT
# resource "aws_nat_gateway" "example" {
#   allocation_id = var.eip
#   subnet_id     = var.nat_gw_subnet

#   tags = merge(
#     {
#       "Name" = format("%s", var.name)
#     },
#     var.tags,
#     var.natgw_tags,
#   )

#   # To ensure proper ordering, it is recommended to add an explicit dependency
#   # on the Internet Gateway for the VPC.
#   depends_on = [aws_internet_gateway.this]
# }


resource "aws_nat_gateway" "nat_gateway" {
  count = length(var.azs)
  allocation_id = aws_eip.nat_eip[count.index].id
  subnet_id     = element(data.aws_subnet_ids.subnets_private.ids, count.index)
  tags = {
    Name = "nat-gateway-${var.azs[count.index]}"
  }
}

resource "aws_eip" "nat_eip" {
  count = length(var.azs)
  vpc      = true
  tags = {
    Name = "nat-eip-${var.azs[count.index]}"
  }
}