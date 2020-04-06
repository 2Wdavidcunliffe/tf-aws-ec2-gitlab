data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

# Locating zone id for supplied domain apex
data "aws_route53_zone" "selected" {
  name = "${var.domain_apex}."
}

data "template_file" "atlantis_repo_conf" {
  template = file("${path.module}/scripts/atlantis_repo.yaml")
}

data "template_file" "aws_config" {
  template = file("${path.module}/scripts/aws_config")
}

data "template_file" "aws_credentials" {
  template = file("${path.module}/scripts/aws_credentials")

  vars = {
    atlantis_user_key    = aws_iam_access_key.atlantis.id
    atlantis_user_secret = aws_iam_access_key.atlantis.secret
  }
}

data "template_file" "gitlab_config" {
  template = "${file("${path.module}/scripts/gitlab.rb.tpl")}"

  vars = {
    url                            = "http://${local.dns_prefix}.${trimsuffix(data.aws_route53_zone.selected.name, ".")}"
    manage_backup_path             = true
    backup_path                    = "/var/opt/gitlab/backups"
    region                         = local.region
    backup_upload_remote_directory = local.s3_bucket
  }
}