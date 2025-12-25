
# We already have a VPC and Subnets created manually
# resource "aws_subnet" "example" {
#   cidr_block = "172.31.1.0/24"
#   map_public_ip_on_launch = true
#   tags = {
#     Name = "terraform-subnet-172-31-1"
#   }
# }

# ====================================================
# Main configuration starts here
# ====================================================

resource "aws_security_group" "ssh_access" {
  name        = "ssh-access-sg"
  description = "Allow inbound traffic"
  vpc_id      = data.aws_vpc.vpc.id

  # we allow all traffic for now
  # ingress {
  #   description = "SSH from anywhere"
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  ingress {
    description = "all traffic from anywhere"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow all traffic from instances associated with this SG (Internal Cluster Comm)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"

    self = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Get the latest Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_instance" "cp_servers" {
  count = var.cp_count
  ami = data.aws_ami.ubuntu.id
  instance_type = var.cp_type
  ipv6_address_count = 1
  subnet_id = data.aws_subnet.my_subnet.id

  security_groups = [aws_security_group.ssh_access.id]
  key_name        = aws_key_pair.app-server-key.key_name
  tags = {
    Name    = "cp-${count.index + 1}"
    Project = "TerraformCluster"
  }
}

resource "aws_instance" "workers_servers" {
  count = var.worker_count
  ami = data.aws_ami.ubuntu.id
  instance_type = var.worker_type
  subnet_id = data.aws_subnet.my_subnet.id #aws_subnet.example.id
  security_groups = [aws_security_group.ssh_access.id]
  key_name        = aws_key_pair.app-server-key.key_name
  tags = {
    Name    = "worker-${count.index + 1}"
    Project = "TerraformCluster"
  }
}

resource "aws_key_pair" "app-server-key" {
  key_name   = "app-server-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "local_file" "ansible_inventory" {
  filename = "inventory"
  content = templatefile("${path.module}/inventory.tpl", {
    control_plane_ips = aws_instance.cp_servers[*].public_ip
    worker_ips        = aws_instance.workers_servers[*].public_ip
  })
}

output "ansible_run" {
  description = "Ansible run command"
  value       = "ansible-playbook -i inventory k8.yml -e 'cp_dns_name=cp.example.com' -e 'he_net_password=dynamic_dns_record_password_here'"
}
