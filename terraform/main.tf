locals {
  region     = "us-east-1"
  dns_prefix = "giitlab"
  s3_bucket  = "gitlab.2wdc.net"
  ssh_private_key = "./scripts/ec2.pem"
}


module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.32.0"

  name = "gitlab"
  cidr = "10.0.0.0/16"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = false

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

resource "aws_security_group" "allow_ssh_tls" {
  name        = "allow_ssh_tls"
  description = "Allow SSH and TLS inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    # TLS (change to whatever ports you need)
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    # HTTP (change to whatever ports you need)
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    # TLS (change to whatever ports you need)
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

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

data "aws_route53_zone" "selected" {
  name = "2wdc.net."
}

resource "aws_route53_record" "gitlab" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${local.dns_prefix}.${data.aws_route53_zone.selected.name}"
  type    = "A"
  ttl     = "30"
  records = [aws_instance.gitlab.public_ip]
}

resource "aws_route53_record" "gitlab_certbot" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "_acme-challenge.${data.aws_route53_zone.selected.name}"
  type    = "A"
  ttl     = "30"
  records = [aws_instance.gitlab.public_ip]
}

data "template_file" "gitlab_config" {
  template = "${file("${path.module}/scripts/gitlab.rb.tpl")}"

  vars = {
    url = "https://${local.dns_prefix}.${trimsuffix(data.aws_route53_zone.selected.name, ".")}"
    manage_backup_path = true
    backup_path = "/var/opt/gitlab/backups"
    region = local.region
    backup_upload_remote_directory = local.s3_bucket
  }
}

resource "aws_instance" "gitlab" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3.medium"
  key_name             = "ec2"
  iam_instance_profile = aws_iam_instance_profile.gitlab_letsencrypt.name
  subnet_id            = module.vpc.public_subnets.0
  security_groups      = [aws_security_group.allow_ssh_tls.id]
  user_data            = templatefile("${path.module}/scripts/userdata.sh.tpl", { url = "${local.dns_prefix}.${trimsuffix(data.aws_route53_zone.selected.name, ".")}" })


  provisioner "file" {
    content = data.template_file.gitlab_config.rendered
    destination = "/tmp/gitlab.rb"

    connection {
        type        = "ssh"
        user        = "ubuntu"
        private_key = file(local.ssh_private_key)
        host        = aws_instance.gitlab.public_ip
      }
  }

  lifecycle {
    ignore_changes = [
      security_groups,
    ]
  }
  tags = {
    Name = "Gitlab-Main"
  }
}

resource "aws_iam_role" "gitlab_letsencrypt" {
  name = "gitlab_letsencrypt_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

}

resource "aws_iam_instance_profile" "gitlab_letsencrypt" {
  name = "gitlab_letsencrypt"
  role = aws_iam_role.gitlab_letsencrypt.name
}

data "aws_iam_policy_document" "gitlab_letsencrypt" {
  statement {
    sid = "route53access"

    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:GetChange"
    ]

    resources = [
      "arn:aws:route53:::*",
    ]
  }

  statement {
    sid = "route53mgmt"

    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets",
    ]

    resources = [
      "arn:aws:route53:::hostedzone/${data.aws_route53_zone.selected.zone_id}",
    ]
  }

  statement {
    sid = "ssm"

    effect = "Allow"

    actions = [
      "ssm:*",
      "ec2messages:GetMessages",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "s3:GetEncryptionConfiguration"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    sid = "s3list"

    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:ListALLMyBucket",
      "s3:HeadBucket",
    ]

    resources = [
      "arn:aws:s3:::*"
    ]
  }
  
  statement {
    sid = "s3"

    effect = "Allow"

    actions = [
      "s3:*",
    ]

    resources = [
      "arn:aws:s3:::${local.s3_bucket}/*"
    ]
  }
}

resource "aws_iam_role_policy" "gitlab_letsencrypt" {
  name   = "gitlab_letsencrypt"
  role   = aws_iam_role.gitlab_letsencrypt.name
  policy = data.aws_iam_policy_document.gitlab_letsencrypt.json
}
