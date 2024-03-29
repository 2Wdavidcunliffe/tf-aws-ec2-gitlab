resource "aws_instance" "gitlab" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3.medium"
  key_name             = "ec2"
  iam_instance_profile = aws_iam_instance_profile.gitlab.name
  subnet_id            = module.vpc.private_subnets.0
  security_groups      = [aws_security_group.allow_ssh_tls.id]
  
  user_data            = templatefile("${path.module}/scripts/userdata.sh.tpl", {
    url                   = "${local.dns_prefix}.${trimsuffix(data.aws_route53_zone.selected.name, ".")}"
    terraform_version     = var.terraform_version
    atlantis_version      = var.atlantis_version
    atlantis_repo_yaml    = data.template_file.atlantis_repo_conf.rendered
    atlantis_secret       = var.atlantis_secret
    aws_config            = data.template_file.aws_config.rendered
    aws_credentials       = data.template_file.aws_credentials.rendered
    gitlab_root_pass      = var.gitlab_root_pass
    gitlab_runners_token  = var.gitlab_runners_token
    gitlab_rb             = data.template_file.gitlab_config.rendered
  })

  lifecycle {
    ignore_changes = [
      security_groups,
    ]
  }
  tags = {
    Name = "Gitlab-Main"
  }
}

resource "aws_s3_bucket" "gitlab-bucket" {
  bucket = local.s3_bucket
  acl    = "bucket-owner-full-control"

  # Comment out prevent_destroy below in lifecycle rule 
  # before enabling this function
  # http://salewski.github.io/2017/04/30/terraform-howto-delete-a-non-empty-aws-s3-bucket.html
  force_destroy = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "log"
    enabled = false

    prefix = "logs/"

    tags = {
      rule      = "log"
      autoclean = false
    }

    transition {
      days          = "30"
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = "60"
      storage_class = "GLACIER"
    }

    expiration {
      days = "90"
    }
  }

  lifecycle {
  # Any Terraform plan that includes a destroy of this resource will
  # result in an error message.
  # http://salewski.github.io/2017/04/30/terraform-howto-delete-a-non-empty-aws-s3-bucket.html
  prevent_destroy = true
  }
}