provider "aws" {
  version = "~> 2.0"
  region  = "us-east-1"
  profile = "2ndwatch"
}

terraform {
  backend "s3" {
    bucket  = "gitlab-backup-2wdc"
    key     = "tf-aws-ec2-s3"
    region  = "us-east-1"
    profile = "2ndwatch"
  }
}


module "vpc" {
    source = "./modules/vpc"

    vpc_name = "test-vpc"
}
