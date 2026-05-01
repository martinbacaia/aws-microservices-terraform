###############################################################################
# VPC + tiered subnet layout (public / private) across N AZs.
#
# Subnet math: with a /16 VPC and N AZs, we carve /20s. cidrsubnet(cidr, 4, i)
# yields 16 distinct /20s — index 0..N-1 = public, index N..2N-1 = private.
# That keeps the address plan deterministic without per-AZ inputs.
###############################################################################

locals {
  az_count = length(var.availability_zones)

  # Map AZ name -> deterministic index (0,1,2…). Sorted so adding a new AZ
  # at the end of the list does not renumber existing subnets.
  az_index = { for idx, az in var.availability_zones : az => idx }

  public_subnets  = { for az, i in local.az_index : az => cidrsubnet(var.cidr_block, 4, i) }
  private_subnets = { for az, i in local.az_index : az => cidrsubnet(var.cidr_block, 4, i + local.az_count) }

  # If single_nat_gateway, only the first AZ gets a NAT; all private subnets
  # route through it. Otherwise one NAT per AZ.
  nat_azs = var.single_nat_gateway ? [var.availability_zones[0]] : var.availability_zones

  base_tags = merge(
    {
      "Name"      = var.name
      "Module"    = "vpc"
      "ManagedBy" = "terraform"
    },
    var.tags,
  )
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.base_tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.base_tags, { Name = "${var.name}-igw" })
}

###############################################################################
# Public subnets — route 0.0.0.0/0 to IGW. ALB and NAT live here; nothing else
# should.
###############################################################################
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false # Defense in depth — instances should be in private subnets anyway.

  tags = merge(local.base_tags, {
    Name                     = "${var.name}-public-${each.key}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1" # Harmless if no EKS; useful if added later.
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.base_tags, { Name = "${var.name}-rt-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

###############################################################################
# Private subnets — egress to internet via NAT (one or per-AZ).
###############################################################################
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(local.base_tags, {
    Name                              = "${var.name}-private-${each.key}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = merge(local.base_tags, { Name = "${var.name}-nat-eip-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.base_tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

# One private route table per AZ; each routes 0/0 at "its" NAT (or the only
# NAT in single-NAT mode).
resource "aws_route_table" "private" {
  for_each = toset(var.availability_zones)

  vpc_id = aws_vpc.this.id
  tags   = merge(local.base_tags, { Name = "${var.name}-rt-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = toset(var.availability_zones)

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[local.nat_azs[0]].id : aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

###############################################################################
# VPC endpoints — keep S3/ECR/Logs traffic off the NAT.
###############################################################################
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]

  tags = merge(local.base_tags, { Name = "${var.name}-vpce-s3" })
}

# Interface endpoints need a security group that allows 443 from the VPC.
resource "aws_security_group" "endpoints" {
  count = var.enable_ecr_endpoints ? 1 : 0

  name        = "${var.name}-vpce"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.base_tags, { Name = "${var.name}-vpce-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count = var.enable_ecr_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from within VPC"
  cidr_ipv4         = aws_vpc.this.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "endpoints_all" {
  count = var.enable_ecr_endpoints ? 1 : 0

  security_group_id = aws_security_group.endpoints[0].id
  description       = "Endpoint ENIs can respond"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

locals {
  ecr_endpoint_services = var.enable_ecr_endpoints ? toset([
    "ecr.api",
    "ecr.dkr",
    "logs",
    "secretsmanager",
  ]) : toset([])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.ecr_endpoint_services

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.base_tags, { Name = "${var.name}-vpce-${each.key}" })
}

###############################################################################
# Flow logs (optional).
###############################################################################
resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  tags              = local.base_tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json
  tags               = local.base_tags
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name   = "publish"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = aws_vpc.this.id
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  traffic_type    = "ALL"

  tags = local.base_tags
}

data "aws_region" "current" {}
