resource "aws_iam_role" "gitlab" {
  name = "gitlab_role"

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

resource "aws_iam_instance_profile" "gitlab" {
  name = "gitlab"
  role = aws_iam_role.gitlab.name
}

data "aws_iam_policy_document" "gitlab" {
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

resource "aws_iam_role_policy" "gitlab" {
  name   = "gitlab"
  role   = aws_iam_role.gitlab.name
  policy = data.aws_iam_policy_document.gitlab.json
}


data "local_file" "AtlantisUserPermissions" {
  filename = "${path.module}/scripts/atlantis_inline_policy.json"
}

resource "aws_iam_user" "atlantis" {
  name = "atlantis"
}

resource "aws_iam_user_policy" "atlantis" {
  name = "AtlantisUserPermissions"
  user = aws_iam_user.atlantis.name

  policy = data.local_file.AtlantisUserPermissions.content
}

resource "aws_iam_access_key" "atlantis" {
  user = aws_iam_user.atlantis.name
}