# Terraform AWS Infrastructure Template for CI/CD Framework
# Production-ready infrastructure with security and scalability best practices

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
  
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "cicd-infrastructure/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "eks_cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.27"
}

# Data sources
data "aws_caller_identity" "current" {}

# VPC Configuration
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment}-cicd-vpc"
    Environment = var.environment
    Purpose     = "CI/CD Infrastructure"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.environment}-cicd-igw"
    Environment = var.environment
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Type        = "Public"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "${var.environment}-private-subnet-${count.index + 1}"
    Environment = var.environment
    Type        = "Private"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# NAT Gateways
resource "aws_eip" "nat" {
  count = length(var.availability_zones)

  domain = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name        = "${var.environment}-nat-eip-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name        = "${var.environment}-nat-gateway-${count.index + 1}"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.environment}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name        = "${var.environment}-private-rt-${count.index + 1}"
    Environment = var.environment
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Groups
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.environment}-eks-cluster-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-eks-cluster-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.environment}-eks-nodes-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-eks-nodes-sg"
    Environment = var.environment
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "${var.environment}-cicd-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_cluster_version

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  encryption_config {
    provider {
      key_arn = aws_kms_key.eks.arn
    }
    resources = ["secrets"]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks_cluster,
  ]

  tags = {
    Name        = "${var.environment}-cicd-cluster"
    Environment = var.environment
  }
}

# EKS Node Groups
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.environment}-cicd-nodes"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  capacity_type  = "ON_DEMAND"
  instance_types = ["t3.large"]

  scaling_config {
    desired_size = 3
    max_size     = 10
    min_size     = 1
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = {
    Name        = "${var.environment}-cicd-nodes"
    Environment = var.environment
  }
}

# Launch Template for EKS Nodes
resource "aws_launch_template" "eks_nodes" {
  name_prefix   = "${var.environment}-eks-nodes-"
  image_id      = data.aws_ami.eks_worker.id
  instance_type = "t3.large"

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    cluster_name        = aws_eks_cluster.main.name
    endpoint           = aws_eks_cluster.main.endpoint
    cluster_auth_base64 = aws_eks_cluster.main.certificate_authority[0].data
  }))

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 100
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_key.ebs.arn
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.environment}-eks-node"
      Environment = var.environment
    }
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-cicd-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.environment}-cicd-db-subnet-group"
    Environment = var.environment
  }
}

# RDS Instance
resource "aws_db_instance" "main" {
  identifier = "${var.environment}-cicd-postgres"

  engine         = "postgres"
  engine_version = "15.3"
  instance_class = "db.t3.medium"

  allocated_storage     = 100
  max_allocated_storage = 1000
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id           = aws_kms_key.rds.arn

  db_name  = "cicddb"
  username = "cicduser"
  password = random_password.db_password.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  skip_final_snapshot = false
  final_snapshot_identifier = "${var.environment}-cicd-postgres-final-snapshot"

  tags = {
    Name        = "${var.environment}-cicd-postgres"
    Environment = var.environment
  }
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.environment}-cicd-cache-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name        = "${var.environment}-cicd-cache-subnet-group"
    Environment = var.environment
  }
}

# ElastiCache Redis Cluster
resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${var.environment}-cicd-redis"
  description                = "Redis cluster for CI/CD framework"

  node_type            = "cache.t3.micro"
  port                 = 6379
  parameter_group_name = "default.redis7"

  num_cache_clusters = 2

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_password.result

  tags = {
    Name        = "${var.environment}-cicd-redis"
    Environment = var.environment
  }
}

# Outputs
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Redis endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  sensitive   = true
}

