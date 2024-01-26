# A Terraform file that creates the AWS resources needed to deploy Hubs Community Edition.

terraform {
  required_version = "1.7.0"
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.2"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.12.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.25.2"
    }
  }
}

provider "aws" {
  region = var.REGION
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

# VPC
resource "aws_vpc" "hubs_ce_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name                                            = "${var.SERVICE_NAME_TAG}-vpc"
    ServiceName                                     = var.SERVICE_NAME_TAG
    EnvName                                         = var.ENV_NAME_TAG
    "kubernetes.io/cluster/${var.SERVICE_NAME_TAG}" = "shared"
  }
}

# 2 Public Subnet
resource "aws_subnet" "hubs_ce_public_subnet1" {
  vpc_id                  = aws_vpc.hubs_ce_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.REGION}a"
  map_public_ip_on_launch = true # 各サブネットに自動でIPが振られるようにする

  tags = {
    Name                                            = "${var.SERVICE_NAME_TAG}-public-subnet1"
    ServiceName                                     = var.SERVICE_NAME_TAG
    EnvName                                         = var.ENV_NAME_TAG
    "kubernetes.io/cluster/${var.SERVICE_NAME_TAG}" = "shared"
    "kubernetes.io/role/elb"                        = 1
  }
}
resource "aws_subnet" "hubs_ce_public_subnet2" {
  vpc_id                  = aws_vpc.hubs_ce_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.REGION}c"
  map_public_ip_on_launch = true

  tags = {
    Name                                            = "${var.SERVICE_NAME_TAG}-public-subnet2"
    ServiceName                                     = var.SERVICE_NAME_TAG
    EnvName                                         = var.ENV_NAME_TAG
    "kubernetes.io/cluster/${var.SERVICE_NAME_TAG}" = "shared"
    "kubernetes.io/role/elb"                        = 1
  }
}

# 2 Private Subnet
resource "aws_subnet" "hubs_ce_private_subnet1" {
  vpc_id            = aws_vpc.hubs_ce_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.REGION}a"

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-private-subnet1"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}
resource "aws_subnet" "hubs_ce_private_subnet2" {
  vpc_id            = aws_vpc.hubs_ce_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "${var.REGION}c"

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-private-subnet2"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# Internet Gateway
resource "aws_internet_gateway" "hubs_ce_igw" {
  vpc_id = aws_vpc.hubs_ce_vpc.id

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-igw"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# Route Table
resource "aws_route_table" "hubs_ce_public_route_table" {
  vpc_id = aws_vpc.hubs_ce_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hubs_ce_igw.id
  }
  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-public-route-table"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# Route Table Association
resource "aws_route_table_association" "hubs_ce_public_route_table_association1" {
  subnet_id      = aws_subnet.hubs_ce_public_subnet1.id
  route_table_id = aws_route_table.hubs_ce_public_route_table.id
}
resource "aws_route_table_association" "hubs_ce_public_route_table_association2" {
  subnet_id      = aws_subnet.hubs_ce_public_subnet2.id
  route_table_id = aws_route_table.hubs_ce_public_route_table.id
}

# EKS Cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = var.SERVICE_NAME_TAG
  cluster_version = "1.27"

  vpc_id                         = aws_vpc.hubs_ce_vpc.id
  subnet_ids                     = [aws_subnet.hubs_ce_public_subnet1.id, aws_subnet.hubs_ce_public_subnet2.id]
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    one = {
      name           = "node-group-1"
      instance_types = [var.NODE_GROUPS_INSTANCE_TYPE]
      min_size       = var.NODE_GROUPS_MIN_SIZE
      max_size       = var.NODE_GROUPS_MAX_SIZE
      desired_size   = var.NODE_GROUPS_DESIRED_CAPACITY

      iam_role_additional_policies = {
        AmazonEFSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
      }
    }
  }

  cluster_addons = {
    coredns = {
      enabled = true
    }
  }

  tags = {
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# Update kubeconfig
resource "null_resource" "update_kubeconfig" {
  triggers = {
    cluster_name = module.eks.cluster_name
  }
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.REGION}"
  }
  depends_on = [module.eks]
}

# HACK: EKS module does not detect changes in desired_capacity, so use null_resource to change desired_capacity
# Detail: https://github.com/bryantbiggs/eks-desired-size-hack
resource "null_resource" "update_desired_size" {
  triggers = {
    desired_size = var.NODE_GROUPS_DESIRED_CAPACITY
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]

    # Note: this requires the awscli to be installed locally where Terraform is executed
    command = <<-EOT
      aws eks update-nodegroup-config \
        --cluster-name ${module.eks.cluster_name} \
        --nodegroup-name ${element(split(":", module.eks.eks_managed_node_groups["one"].node_group_id), 1)} \
        --scaling-config desiredSize=${var.NODE_GROUPS_DESIRED_CAPACITY} \
        --region ${var.REGION}
    EOT
  }

  depends_on = [module.eks, null_resource.update_kubeconfig]
}

# Security Group Ingress Rules For EKS nodegroup
resource "aws_vpc_security_group_ingress_rule" "hubs_ce_eks_node_security_group_tcp_4443" {
  security_group_id = module.eks.node_security_group_id
  ip_protocol       = "tcp"
  from_port         = 4443
  to_port           = 4443
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "hubs_ce_eks_node_security_group_tcp_5349" {
  security_group_id = module.eks.node_security_group_id
  ip_protocol       = "tcp"
  from_port         = 5349
  to_port           = 5349
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "hubs_ce_eks_node_security_group_udp_35000_60000" {
  security_group_id = module.eks.node_security_group_id
  ip_protocol       = "udp"
  from_port         = 35000
  to_port           = 60000
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "hubs_ce_eks_node_security_group_tcp_443" {
  security_group_id = module.eks.node_security_group_id
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_vpc_security_group_ingress_rule" "hubs_ce_eks_node_security_group_tcp_80" {
  security_group_id = module.eks.node_security_group_id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Subnet Group For RDS
resource "aws_db_subnet_group" "hubs_ce_db_subnet_group" {
  name       = "${var.SERVICE_NAME_TAG}-db-subnet-group"
  subnet_ids = [aws_subnet.hubs_ce_private_subnet1.id, aws_subnet.hubs_ce_private_subnet2.id]

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-db-subnet-group"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# Security Group For RDS
resource "aws_security_group" "hubs_ce_db_security_group" {
  name        = "${var.SERVICE_NAME_TAG}-db-security-group"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.hubs_ce_vpc.id

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-db-security-group"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}
# Allow access to DB from EKS node
resource "aws_vpc_security_group_ingress_rule" "hubs_ce_db_security_group_tcp_5432" {
  security_group_id            = aws_security_group.hubs_ce_db_security_group.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = module.eks.node_security_group_id
}
# Allow access to EKS node from DB
resource "aws_vpc_security_group_ingress_rule" "hubs_ce_eks_node_security_group_tcp_5432" {
  security_group_id            = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.hubs_ce_db_security_group.id
}

# RDS Cluster
resource "aws_rds_cluster" "hubs_ce_db" {
  cluster_identifier        = "${var.SERVICE_NAME_TAG}-database-1"
  engine                    = "aurora-postgresql"
  engine_version            = var.DB_ENGINE_VERSION
  database_name             = "retdb"
  master_username           = "postgres"
  master_password           = var.DB_MASTER_PASSWORD
  backup_retention_period   = var.DB_BACKUP_RETENTION_PERIOD
  db_subnet_group_name      = aws_db_subnet_group.hubs_ce_db_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.hubs_ce_db_security_group.id]
  final_snapshot_identifier = false # Set to true if the last snapshot is taken on deletion
  skip_final_snapshot       = true  # Set to false if the last snapshot is taken on deletion
  # final_snapshot_identifier = "${var.SERVICE_NAME_TAG}-database-final-snapshot-${timestamp()}"  # Uncomment out if you want to take a final snapshot on deletion

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-database"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# RDS Instance
resource "aws_rds_cluster_instance" "hubs_ce_db_instance" {
  identifier           = "${var.SERVICE_NAME_TAG}-database-instance-1"
  cluster_identifier   = aws_rds_cluster.hubs_ce_db.id
  instance_class       = var.DB_INSTANCE_CLASS
  engine               = "aurora-postgresql"
  engine_version       = var.DB_ENGINE_VERSION
  db_subnet_group_name = aws_db_subnet_group.hubs_ce_db_subnet_group.name

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-database-instance"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# EFS
resource "aws_efs_file_system" "hubs_ce_efs" {
  creation_token = "${var.SERVICE_NAME_TAG}-efs"
  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-efs"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# Security Group for EFS
resource "aws_security_group" "hubs_ce_efs_security_group" {
  name        = "${var.SERVICE_NAME_TAG}-efs-security-group"
  description = "Security group for EFS"
  vpc_id      = aws_vpc.hubs_ce_vpc.id

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-efs-security-group"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

# Allow all traffic access from EKS nodes to EFS
resource "aws_vpc_security_group_ingress_rule" "hubs_ce_efs_security_group_all" {
  security_group_id            = aws_security_group.hubs_ce_efs_security_group.id
  ip_protocol                  = "-1"
  referenced_security_group_id = module.eks.node_security_group_id
}

# Create mount targets for EFS
resource "aws_efs_mount_target" "hubs_ce_efs_mount_target1" {
  file_system_id  = aws_efs_file_system.hubs_ce_efs.id
  subnet_id       = aws_subnet.hubs_ce_public_subnet1.id
  security_groups = [aws_security_group.hubs_ce_efs_security_group.id]
}
resource "aws_efs_mount_target" "hubs_ce_efs_mount_target2" {
  file_system_id  = aws_efs_file_system.hubs_ce_efs.id
  subnet_id       = aws_subnet.hubs_ce_public_subnet2.id
  security_groups = [aws_security_group.hubs_ce_efs_security_group.id]
}

# EFS CSI Driver for EKS
# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest
# https://github.com/terraform-aws-modules/terraform-aws-iam/blob/master/examples/iam-role-for-service-accounts-eks/main.tf
# https://registry.terraform.io/modules/terraform-aws-modules/iam/aws/latest/submodules/iam-role-for-service-accounts-eks
module "efs_csi_irsa_role" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  role_name             = "efs-csi-irsa-role"
  attach_efs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }

  tags = {
    Name        = "${var.SERVICE_NAME_TAG}-efs-csi-irsa-role"
    ServiceName = var.SERVICE_NAME_TAG
    EnvName     = var.ENV_NAME_TAG
  }
}

resource "helm_release" "aws_efs_csi_driver" {
  chart      = "aws-efs-csi-driver"
  name       = "aws-efs-csi-driver"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.eu-west-3.amazonaws.com/eks/aws-efs-csi-driver"
  }

  set {
    name  = "controller.serviceAccount.create"
    value = true
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.efs_csi_irsa_role.iam_role_arn
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "efs-csi-controller-sa"
  }
}

