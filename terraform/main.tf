module "bastion" {
  source  = "Guimove/bastion/aws"
  version = "1.2.0"
  bucket_name = "gitlab-bastion-2wdc"
  region = local.region
  vpc_id = module.vpc.vpc_id
  is_lb_private = false
  bastion_host_key_pair = "ec2"
  create_dns_record = true
  hosted_zone_name = data.aws_route53_zone.selected.zone_id
  bastion_record_name = trimsuffix("ssh.${data.aws_route53_zone.selected.name}", ".")
  elb_subnets = module.vpc.public_subnets
  auto_scaling_group_subnets = module.vpc.public_subnets
  tags = {
    "name" = "gitlab_bastion",
    "description" = "allows ssh access into vpc"
  }
}

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
  })


  provisioner "file" {
    content     = data.template_file.gitlab_config.rendered
    destination = "/tmp/gitlab.rb"

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file(local.ssh_private_key)
      host        = self.private_ip
      timeout     = "10m"

      bastion_host        = module.bastion.elb_ip
      bastion_user        = "ec2-user"
      bastion_private_key = file(local.ssh_private_key)
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

  depends_on = [module.bastion.elb_ip]
}