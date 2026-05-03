terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0" # Using 4.0 to avoid GPG key issue
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# Get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  owners = ["099720109477"]
}

# Security Group
resource "aws_security_group" "k3s_sg" {
  name_prefix = "k3s-sg-"
  description = "Security group for K3s cluster"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k3s-security-group"
  }
}

# EC2 Instance
resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]
  key_name               = var.key_name

  user_data = <<-EOF
  #!/bin/bash
  # NO set -e — we handle errors manually

  # Log everything
  exec > /var/log/user-data.log 2>&1

  echo "=== Starting setup ==="

  # Update system
  apt-get update -y

  # Install Docker
  apt-get install -y docker.io curl
  systemctl start docker
  systemctl enable docker
  usermod -aG docker ubuntu

  # Install K3s (without --docker flag, use containerd instead — more stable)
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644" sh -

  # Wait for K3s to actually be ready
  echo "Waiting for K3s..."
  for i in $(seq 1 30); do
    if systemctl is-active --quiet k3s; then
      echo "K3s service is active"
      break
    fi
    echo "Attempt $i/30 - waiting..."
    sleep 10
  done

  # Wait for node to be Ready
  for i in $(seq 1 20); do
    if /usr/local/bin/kubectl --kubeconfig=/etc/rancher/k3s/k3s.yaml get nodes | grep -q "Ready"; then
      echo "Node is Ready!"
      break
    fi
    echo "Node not ready yet... ($i/20)"
    sleep 10
  done

  # Copy kubeconfig for ubuntu user
  mkdir -p /home/ubuntu/.kube
  cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
  chown -R ubuntu:ubuntu /home/ubuntu/.kube
  chmod 600 /home/ubuntu/.kube/config

  # Also set it globally
  echo 'export KUBECONFIG=/home/ubuntu/.kube/config' >> /home/ubuntu/.bashrc
  echo 'export KUBECONFIG=/home/ubuntu/.kube/config' >> /home/ubuntu/.profile

  echo "=== Setup complete ==="
EOF

  tags = {
    Name = "k3s-server"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}

