output "gitlab_values" {
  value = {
    "PRV_IP"   = aws_instance.gitlab.private_ip,
    "HTTP"     = "https://${aws_route53_record.gitlab_web.name}",
    "SSH_INFO" = "ssh ubuntu@${aws_instance.gitlab.private_ip} -i ~/Downloads/ec2.pem",
    "BACKUP_BUCKET" = local.s3_bucket
  }
}

output "bastion_values" {
  value = {
    "SSH_INFO" = "ssh ec2-user@${trimsuffix("ssh.${data.aws_route53_zone.selected.name}", ".")} -i ~/Downloads.ec2.pem",
    "LOG_BUCKET" = module.bastion.bucket_name
  }
}

output "secrets" {
  value = {
    "GITLAB_ROOT_TEMP_PASS" = var.gitlab_root_pass,
    "ATLANTIS_SECRET" = var.atlantis_secret,
    "GITLAB_RUNNERS_TOKEN" = var.gitlab_runners_token,
    "SSH_KEY_LOCATION" = local.ssh_private_key
  }
}