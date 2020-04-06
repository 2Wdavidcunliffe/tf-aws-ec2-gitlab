output "gitlab_values" {
  value = {
    "HTTP"     = "https://${aws_route53_record.gitlab_web.name}",
    "SSH_INFO" = "ssh ubuntu@${aws_route53_record.gitlab_ssh.fqdn} -i ~/Downloads/ec2.pem",
    "BACKUP_BUCKET" = local.s3_bucket
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