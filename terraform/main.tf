terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"  # Using 4.0 to avoid GPG key issue
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
    set -e
    
    # Update system
    apt-get update -y
    
    # Install Docker
    apt-get install -y docker.io
    systemctl start docker
    systemctl enable docker
    
    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    
    # Install K3s
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --docker" sh -
    
    # Wait for K3s to be ready
    sleep 30
    
    # Save kubeconfig for ubuntu user
    mkdir -p /home/ubuntu/.kube
    cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
    chown -R ubuntu:ubuntu /home/ubuntu/.kube
    
    echo "K3s installation complete"
  EOF

  tags = {
    Name = "k3s-server"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
}

# Outputs
output "instance_public_ip" {
  value = aws_instance.k3s_server.public_ip
  description = "Public IP of K3s server"
}

output "app_url" {
  value = "http://${aws_instance.k3s_server.public_ip}:30080"
  description = "URL to access the application"
}

output "ssh_command" {
  value = "ssh -i ${var.key_name}.pem ubuntu@${aws_instance.k3s_server.public_ip}"
  description = "SSH command to connect to the instance"
}