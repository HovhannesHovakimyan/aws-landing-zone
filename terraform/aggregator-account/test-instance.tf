# Test EC2 instance for TGW connectivity validation via ping
# This instance is placed in an app-tier subnet that routes to the TGW for
# cross-spoke connectivity testing.

# ── App-tier subnets ──────────────────────────────────────────────────────────

resource "aws_subnet" "app" {
  provider          = aws.spoke
  count             = 2
  vpc_id            = aws_vpc.spoke.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.tgw_subnet_azs[count.index]

  tags = {
    Name = "${var.vpc_name}-app-${var.tgw_subnet_azs[count.index]}"
  }
}

# ── Route table for app-tier subnets ──────────────────────────────────────────

resource "aws_route_table" "app" {
  provider = aws.spoke
  vpc_id   = aws_vpc.spoke.id

  tags = {
    Name = "${var.vpc_name}-app-rt"
  }
}

resource "aws_route_table_association" "app" {
  provider       = aws.spoke
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# Routes from app tier to TGW for cross-spoke traffic
resource "aws_route" "app_to_tgw" {
  provider               = aws.spoke
  for_each               = local.spoke_routes
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = each.value
  transit_gateway_id     = local.network_hub_state.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

# ── Security group for test instance ──────────────────────────────────────────

resource "aws_security_group" "test" {
  provider    = aws.spoke
  name        = "${var.vpc_name}-test-sg"
  description = "Security group for test EC2 instance (ping/SSH)"
  vpc_id      = aws_vpc.spoke.id

  # Allow ICMP (ping) from anywhere within RFC1918
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  # Allow SSH from anywhere (restrict as needed)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.vpc_name}-test-sg"
  }
}

# ── IAM role for EC2 (Systems Manager access) ────────────────────────────────

resource "aws_iam_role" "test_instance" {
  provider = aws.spoke
  name     = "${var.vpc_name}-test-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.vpc_name}-test-instance-role"
  }
}

resource "aws_iam_role_policy_attachment" "test_instance_ssm" {
  provider       = aws.spoke
  role           = aws_iam_role.test_instance.name
  policy_arn     = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "test_instance" {
  provider = aws.spoke
  name     = "${var.vpc_name}-test-instance-profile"
  role     = aws_iam_role.test_instance.name
}

# ── Test EC2 instance ─────────────────────────────────────────────────────────

# Use latest Amazon Linux 2 AMI
data "aws_ami" "al2" {
  provider    = aws.spoke
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "test" {
  provider                    = aws.spoke
  ami                         = data.aws_ami.al2.id
  instance_type               = "t3.nano"
  subnet_id                   = aws_subnet.app[0].id
  vpc_security_group_ids      = [aws_security_group.test.id]
  iam_instance_profile        = aws_iam_instance_profile.test_instance.name
  associate_public_ip_address = true

  tags = {
    Name = "${var.vpc_name}-test-instance"
  }
}
