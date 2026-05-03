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
  sensitive = true
}