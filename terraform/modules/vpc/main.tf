# Day 4: VPC module — subnets across 2 AZs, route tables.
# No NAT gateway by design (costs real money on real AWS, unnecessary
# for this project's demo) — see root README budget notes.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.env}-vpc"
    Environment = var.env
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.env}-igw"
    Environment = var.env
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.env}-public-${var.azs[count.index]}"
    Environment = var.env
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name        = "${var.env}-private-${var.azs[count.index]}"
    Environment = var.env
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "${var.env}-public-rt"
    Environment = var.env
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets get a route table with no NAT route — intentional,
# see module note above. Private workloads reach the internet via
# a NAT gateway only if one is added later for the real-AWS path.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.env}-private-rt"
    Environment = var.env
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# App tier: reachable only from inside the VPC. Nothing from 0.0.0.0/0 —
# public traffic is expected to arrive via a load balancer in front, which
# is what the real-AWS path would add.
resource "aws_security_group" "app" {
  name        = "${var.env}-app-sg"
  description = "App tier for ${var.env}"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "App port, VPC-internal only"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Egress is enumerated rather than left wide open. An unrestricted egress
  # rule is what lets a compromised container reach an arbitrary host, and
  # it is the default almost everywhere.
  egress {
    description = "HTTPS to the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS over UDP, VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "DNS over TCP, VPC resolver"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "${var.env}-app-sg"
    Environment = var.env
  }
}

# Every VPC ships with a default security group that allows all traffic
# between anything assigned to it. Nothing here uses it, so it is emptied
# rather than left as a way to accidentally bypass the rules above.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "${var.env}-default-sg-locked"
    Environment = var.env
  }
}
