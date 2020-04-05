module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.32.0"

  name = "gitlab"
  cidr = "10.0.0.0/16"

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

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
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    # Please restrict your ingress to only necessary IPs and ports.
    # Opening to 0.0.0.0/0 can lead to security vulnerabilities.
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    # HTTP for Atlanits(change to whatever ports you need)
    from_port = 8888
    to_port   = 8888
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

resource "aws_security_group" "secgroup_gitlab_web_lb" {

	name = "GITLAB-WEB-LB"

	vpc_id = module.vpc.vpc_id

	ingress {
		from_port = 443
		to_port = 443
		protocol = "tcp"
		cidr_blocks = [
			"0.0.0.0/0"
		]
	}

  	ingress {
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = [
			"0.0.0.0/0"
		]
	}

  ingress {
		from_port = 8888
		to_port = 8888
		protocol = "tcp"
		cidr_blocks = [
			"0.0.0.0/0"
		]
	}

	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}

	tags = {
		Name = "GITLAB-WEB-LB"
	}

}

resource "aws_acm_certificate" "domain_cert" {
  domain_name       = data.aws_route53_zone.selected.name
  subject_alternative_names = ["gitlab.${data.aws_route53_zone.selected.name}", "atlantis.${data.aws_route53_zone.selected.name}", "ssh.${data.aws_route53_zone.selected.name}"]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [subject_alternative_names]
  }
}

resource "aws_route53_record" "validation" {
  count   = length(concat([aws_acm_certificate.domain_cert.domain_name], aws_acm_certificate.domain_cert.subject_alternative_names))
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = element(aws_acm_certificate.domain_cert.domain_validation_options, count.index)["resource_record_name"]
  type    = element(aws_acm_certificate.domain_cert.domain_validation_options, count.index)["resource_record_type"]
  ttl     = "60"
  records = [element(aws_acm_certificate.domain_cert.domain_validation_options, count.index)["resource_record_value"]]
  
  allow_overwrite = true

  depends_on = [aws_acm_certificate.domain_cert]
}

resource "aws_acm_certificate_validation" "domain_cert" {
  certificate_arn = aws_acm_certificate.domain_cert.arn

  validation_record_fqdns = aws_route53_record.validation.*.fqdn
}

resource "aws_lb" "gitlab_web" {
  name               = "gitlab-web"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.secgroup_gitlab_web_lb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false
}

resource "aws_lb_listener" "gitlab_web_ssl" {
  load_balancer_arn = aws_lb.gitlab_web.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.domain_cert.id

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gitlab_web.arn
  }
}

resource "aws_lb_listener" "gitlab_web_http_redirect" {
  load_balancer_arn = aws_lb.gitlab_web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
      type = "redirect"

      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
  }
}

resource "aws_lb_target_group" "gitlab_web" {
  name     = "gitlab-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled = true
    interval = 30
    timeout = 10
    healthy_threshold = 3
    unhealthy_threshold = 3
    path = "/users/sign_in"
    matcher = "200"
  }
}

resource "aws_lb_target_group_attachment" "gitlab_web" {
  target_group_arn = aws_lb_target_group.gitlab_web.arn
  target_id        = aws_instance.gitlab.id
  port             = 80
}

resource "aws_route53_record" "gitlab_web" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = trimsuffix("${local.dns_prefix}.${data.aws_route53_zone.selected.name}", ".")
  type    = "A"

  alias {
    name                   = aws_lb.gitlab_web.dns_name
    zone_id                = aws_lb.gitlab_web.zone_id
    evaluate_target_health = true
  }

  allow_overwrite = true

  depends_on = [aws_acm_certificate.domain_cert]
}

resource "aws_lb" "atlantis_web" {
  name               = "atlantis-web"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.secgroup_gitlab_web_lb.id]
  subnets            = [module.vpc.public_subnets.0,module.vpc.public_subnets.1]

  enable_deletion_protection = false
}

resource "aws_lb_listener" "atlantis_web" {
  load_balancer_arn = aws_lb.atlantis_web.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.domain_cert.id

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.atlantis_web.arn
  }
}

resource "aws_lb_target_group" "atlantis_web" {
  name     = "atlantis-web"
  port     = 8888
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled = true
    interval = 30
    timeout = 10
    healthy_threshold = 3
    unhealthy_threshold = 3
    path = "/"
    matcher = "200"
  }
}

resource "aws_lb_target_group_attachment" "atlantis_web" {
  target_group_arn = aws_lb_target_group.atlantis_web.arn
  target_id        = aws_instance.gitlab.id
  port             = 8888
}

resource "aws_route53_record" "atlantis_web" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = trimsuffix("atlantis.${data.aws_route53_zone.selected.name}", ".")
  type    = "A"

  alias {
    name                   = aws_lb.atlantis_web.dns_name
    zone_id                = aws_lb.atlantis_web.zone_id
    evaluate_target_health = true
  }

  allow_overwrite = true

  depends_on = [aws_acm_certificate.domain_cert]
}