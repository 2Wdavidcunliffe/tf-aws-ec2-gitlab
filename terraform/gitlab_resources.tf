resource "aws_s3_bucket" "gitlab_backup" {
  bucket = "gitlab-s3-resources-${trimsuffix(data.aws_route53_zone.selected.name, ".")}"
  acl    = "private"
}