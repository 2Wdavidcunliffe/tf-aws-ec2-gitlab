output "gitlab_values" {
  value = {
    "PUB_IP"   = aws_instance.gitlab.public_ip,
    "HTTP"     = "https://${aws_route53_record.gitlab_web.name}"
    "SSH_INFO" = "ssh ubuntu@${aws_instance.gitlab.public_ip} -i ~/Downloads/ec2.pem",
  }
}