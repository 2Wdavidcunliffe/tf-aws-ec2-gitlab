locals {
  region          = "us-east-1"
  dns_prefix      = "gitlab"
  s3_bucket       = "gitlab.2wdc.net"
  ssh_private_key = "./scripts/ec2.pem"

  default_tags = {
    ManagedBy      = "Terraform"
    "tf:repo-name" = "tf-aws-ec2-gitlab"
  }
}

variable "domain_apex" {
  description = "The name of a Hosted Zone within Route53. The hostname of the Atlantis service will be 'atlantis.{var.domain_apex}'."
  default     = "2wdc.net"
}

# Instance settings
variable "terraform_version" {
  description = "The version of Terraform to install."
  default     = "0.12.23"
}

variable "atlantis_version" {
  description = "The version of Atlantis to install."
  default     = "0.11.1"
}

variable "gitlab_root_pass" {
  description = "This is to set the intial password of gitlab"
}

variable "atlantis_secret" {
  description = "This is the secret used to work with webhook api calls. What you set here is what you use in gitlab when talking to atlantis."
}

variable "gitlab_runners_token" {
  description = "This is to set the runners token used to connect to gitlab"
  default = "7u3GyKA679fEqf-"
}