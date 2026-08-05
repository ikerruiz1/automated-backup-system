data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current_workload" {}

# -------------------------------------------------------------------------
# KMS Customer Managed Key (CMK)
# -------------------------------------------------------------------------
resource "aws_kms_key" "enterprise_cmk" {
  description             = "CMK to encrypt EBS, RDS, S3 and Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags                    = { Name = "${var.project_name}-cmk" }
}

resource "aws_kms_alias" "enterprise_cmk_alias" {
  name          = "alias/${var.project_name}-cmk"
  target_key_id = aws_kms_key.enterprise_cmk.key_id
}

# -------------------------------------------------------------------------
# Network (Multi-AZ VPC & Routing)
# -------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags              = { Name = "${var.project_name}-private-subnet-${count.index + 1}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.project_name}-rds-subnets"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${var.project_name}-rds-subnet-group" }
}

# -------------------------------------------------------------------------
# Security Groups (Zero Trust)
# -------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints_sg" {
  name        = "${var.project_name}-vpce-sg"
  description = "Allow internal traffic for VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow TLS inbound traffic from internal VPC CIDR for endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow HTTPS outbound traffic only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security Group for EC2 (No public access)"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow HTTPS outbound traffic for updates and API calls"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Security Group for RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow PostgreSQL inbound traffic from EC2 security group"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    description = "Allow outbound traffic internally to VPC only"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }
}

# -------------------------------------------------------------------------
# AWS PrivateLink (VPC Endpoints instead of NAT Gateway)
# -------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}

resource "aws_vpc_endpoint" "kms_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.kms"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "secretsmanager_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssm_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages_interface" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints_sg.id]
  private_dns_enabled = true
}

# -------------------------------------------------------------------------
# Secrets Manager (Dynamic RDS credentials)
# -------------------------------------------------------------------------
resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name       = "${var.project_name}-rds-credentials"
  kms_key_id = aws_kms_key.enterprise_cmk.arn
}

resource "aws_secretsmanager_secret_version" "db_credentials_version" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = "admin_user"
    password = random_password.db_password.result
  })
}

# -------------------------------------------------------------------------
# Workloads (EC2, RDS, Main S3)
# -------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-ec2-ssm-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private[0].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  ebs_optimized          = true
  monitoring             = true

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
    encrypted   = true
    kms_key_id  = aws_kms_key.enterprise_cmk.arn
  }

  tags = {
    Name   = "${var.project_name}-app-server"
    Backup = "true"
  }
}

# IAM Role for RDS Enhanced Monitoring (Requerido para CKV_AWS_118)
resource "aws_iam_role" "rds_monitoring_role" {
  name = "${var.project_name}-rds-monitoring-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_policy" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# RDS Database with all security measures activated for Checkov
resource "aws_db_instance" "enterprise_db" {
  identifier                 = "${var.project_name}-db"
  allocated_storage          = 20
  storage_type               = "gp3"
  engine                     = "postgres"
  engine_version             = "15"
  instance_class             = "db.t3.micro"
  backup_retention_period    = 0
  db_subnet_group_name       = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids     = [aws_security_group.rds_sg.id]
  multi_az                   = true
  storage_encrypted          = true
  kms_key_id                 = aws_kms_key.enterprise_cmk.arn
  username                   = "admin_user"
  password                   = random_password.db_password.result
  skip_final_snapshot        = true
  auto_minor_version_upgrade = true

  # Security fixes for Checkov:
  deletion_protection                 = true
  iam_database_authentication_enabled = true
  performance_insights_enabled        = true
  performance_insights_kms_key_id     = aws_kms_key.enterprise_cmk.arn
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]
  monitoring_interval                 = 60
  monitoring_role_arn                 = aws_iam_role.rds_monitoring_role.arn

  tags = {
    Name   = "${var.project_name}-db"
    Backup = "true"
  }
}

resource "aws_s3_bucket" "secure_data_bucket" {
  bucket        = "${var.project_name}-secure-data-${data.aws_caller_identity.current_workload.account_id}"
  force_destroy = true
  tags = {
    Name   = "${var.project_name}-secure-data"
    Backup = "true"
  }
}

# Dynamic injection of real data for backup validation
resource "aws_s3_object" "sample_data" {
  bucket       = aws_s3_bucket.secure_data_bucket.id
  key          = "critical-business-data.txt"
  content      = "CONFIDENTIAL: This file simulates critical business data to validate complete recovery against incidents or ransomware."
  content_type = "text/plain"
  kms_key_id   = aws_kms_key.enterprise_cmk.arn

  depends_on = [
    aws_s3_bucket_server_side_encryption_configuration.secure_data_encryption
  ]
}

resource "aws_s3_bucket_public_access_block" "secure_data_block" {
  bucket                  = aws_s3_bucket.secure_data_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "secure_data_versioning" {
  bucket = aws_s3_bucket.secure_data_bucket.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secure_data_encryption" {
  bucket = aws_s3_bucket.secure_data_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.enterprise_cmk.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# -------------------------------------------------------------------------
# Observability and Auditing
# -------------------------------------------------------------------------

# 1. Centralized bucket for S3 Logs
resource "aws_s3_bucket" "log_bucket" {
  bucket        = "${var.project_name}-logs-${data.aws_caller_identity.current_workload.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "log_bucket_pab" {
  bucket                  = aws_s3_bucket.log_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "log_bucket_policy" {
  bucket = aws_s3_bucket.log_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3ServerAccessLogsPolicy"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.log_bucket.arn}/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current_workload.account_id }
        }
      }
    ]
  })
}

# Linking logging to the existing data bucket
resource "aws_s3_bucket_logging" "secure_data_logging" {
  bucket        = aws_s3_bucket.secure_data_bucket.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "secure-data-logs/"

  depends_on = [aws_s3_bucket_policy.log_bucket_policy]
}

# 2. Infrastructure for VPC Flow Logs
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.project_name}-flow-logs"
  retention_in_days = 365
}

resource "aws_iam_role" "vpc_flow_logs_role" {
  name = "${var.project_name}-vpc-flow-logs-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "vpc-flow-logs.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs_policy" {
  name = "${var.project_name}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Effect   = "Allow"
      Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn    = aws_iam_role.vpc_flow_logs_role.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}
