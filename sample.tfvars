# -----------------------------------
#      Variables for sample
# -----------------------------------
# Environment name tag
ENV_NAME_TAG = "develop"
# Service name tag
SERVICE_NAME_TAG = "sample"
# Region
REGION = "us-east-1"
# Instance type for EKS node group
NODE_GROUPS_INSTANCE_TYPE = "c5.2xlarge"
# EKS node group desired capacity
NODE_GROUPS_DESIRED_CAPACITY = 3
#  EKS node group min size
NODE_GROUPS_MIN_SIZE = 3
# EKS node group max size
NODE_GROUPS_MAX_SIZE = 5
# Master username of RDS
DB_MASTER_USERNAME = "postgres"
# Master password of RDS
DB_MASTER_PASSWORD = "XXXXXXXXX"
# Engine version of RDS (12.17 is the version tested by hubs)
DB_ENGINE_VERSION = "12.17"
# Instance class of RDS
DB_INSTANCE_CLASS = "db.t3.medium"
# Backup retention period of RDS
DB_BACKUP_RETENTION_PERIOD = 5
