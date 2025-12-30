# =========================================
# Set up
# =========================================

# Setting up AWS provider
provider "aws" {
  region     = var.region
  access_key = var.access_key
  secret_key = var.secret_key
}

variable "region" {
  description = "AWS region"
  default     = "eu-north-1" # Stockholm
}

variable "access_key" {
  description = "AWS access key"
}

variable "secret_key" {
  description = "AWS secret key"
}

variable "vpc_id" {
  description = "AWS vpc id"
}

variable "cp_count" {
  description = "Number of control plane nodes"
  default     = 1
}

variable "cp_type" {
  description = "Type of control plane nodes"
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of worker nodes"
  default     = 3
}

variable "worker_type" {
  description = "Type of worker nodes"
  default     = "t3.medium"
}

# =========================================
# Fetch existing VPC and Subnet information
# =========================================

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

data "aws_subnet" "my_subnet" {
  vpc_id     = data.aws_vpc.vpc.id
  cidr_block = "172.31.16.0/20"
  filter {
    name   = "state"
    values = ["available"]
  }
}
