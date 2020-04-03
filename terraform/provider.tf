provider "aws" {
  version = "~> 2.43"
  region  = "us-east-1"
  profile = "2w-sandbox"
}

terraform {
  backend "s3" {
    bucket  = "dcunliffe-terraform-state"
    key     = "tf-aws-ec2-gitlab"
    region  = "us-east-1"
    profile = "2w-sandbox"
  }
}
