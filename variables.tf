
# Variables
variable "ENV_NAME_TAG" {
  type = string
}

variable "SERVICE_NAME_TAG" {
  type = string
}

variable "REGION" {
  type = string
}

variable "NODE_GROUPS_INSTANCE_TYPE" {
  type = string
}

variable "NODE_GROUPS_DESIRED_CAPACITY" {
  type = number
}

variable "NODE_GROUPS_MIN_SIZE" {
  type = number
}

variable "NODE_GROUPS_MAX_SIZE" {
  type = number
}

variable "DB_MASTER_USERNAME" {
  type = string
}

variable "DB_MASTER_PASSWORD" {
  type = string
}

variable "DB_ENGINE_VERSION" {
  type = string
}

variable "DB_INSTANCE_CLASS" {
  type = string
}

variable "DB_BACKUP_RETENTION_PERIOD" {
  type = number
}