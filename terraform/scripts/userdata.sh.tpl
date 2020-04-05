#!/bin/bash

echo "===================Updating packages and sources==================="
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

echo "===================Set SSH Keep Alive====================="
# Server setup take s along while this will keep connection open
ClientAliveInterval 30 >> /etc/ssh/sshd_config
ClientAliveCountMax 2 >> /etc/ssh/sshd_config
systemctl restart sshd

echo "===================Installing tools for Atlantis and Gitlab==================="
apt-get install -y curl openssh-server ca-certificates debconf-doc python-pip jq zip
debconf-set-selections <<< "postfix postfix/mailname string ${url}"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install --assume-yes postfix
pip install awscli

echo "===================Installing gitlab this will take a moment==================="
curl -s https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
GITLAB_ROOT_PASSWORD="${gitlab_root_pass}" GITLAB_SHARED_RUNNERS_REGISTRATION_TOKEN="${gitlab_runners_token}" EXTERNAL_URL="http://${url}" apt-get install -y gitlab-ce


echo "===================Configuring Gitlab====================="
while [ ! -f /tmp/gitlab.rb ]
do
    echo "Still waiting on gitlab.rb file upload..."
    sleep 2 # or less like 0.2
done
cp /tmp/gitlab.rb /etc/gitlab/gitlab.rb
gitlab-ctl reconfigure
gitlab-ctl restart

echo "===================Building Root User API Token====================="
sleep 10
atlantis_api=`gitlab-rails runner "user = User.where(id: 1).first; personal_access_token = User.find(1).personal_access_tokens.create(name: 'atlantis',impersonation: false,scopes: [:api]); puts personal_access_token.token"`


echo "===================Configuring Backup for Gitlab====================="
# Setup Backup Cron set for 2am, bucket needs to be setup in AWS account outside of this repository
crontab -l | { cat; echo "0 2 * * * /opt/gitlab/bin/gitlab-backup create CRON=1"; } | crontab -
crontab -l | { cat; echo "0 2 * * * aws s3 cp /etc/gitlab/$(date +%s)-gitlab-secrets.json s3://gitlab.2wdc.net/"; } | crontab -
crontab -l | { cat; echo "0 2 * * * aws s3 cp /etc/gitlab/$(date +%s)-gitlab.rb s3://gitlab.2wdc.net/"; } | crontab -


echo "===================Building Atlantis Service User==================="
mkdir /usr/local/atlantis
useradd -r -s /bin/false atlantis -d /usr/local/atlantis

mkdir /root/.aws/
mkdir /usr/local/atlantis/.aws/

tee /tmp/aws_config <<EOF >/dev/null
${aws_config}
EOF

cp /tmp/aws_config /root/.aws/config
mv /tmp/aws_config /usr/local/atlantis/.aws/config

tee /tmp/aws_credentials <<EOF >/dev/null
${aws_credentials}
EOF

cp /tmp/aws_credentials /root/.aws/credentials
mv /tmp/aws_credentials /usr/local/atlantis/.aws/credentials

echo "===================Fetching Terraform==================="
cd /tmp
# wget https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip -O terraform.zip --quiet
wget $(echo "https://releases.hashicorp.com/terraform/$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r -M '.current_version')/terraform_$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r -M '.current_version')_linux_amd64.zip") -O terraform.zip --quiet

echo "===================Installing Terraform==================="
unzip terraform.zip >/dev/null
chmod +x terraform
mv terraform /usr/local/bin/terraform

echo "===================Fetching Atlants==================="
# wget https://github.com/runatlantis/atlantis/releases/download/v${atlantis_version}/atlantis_linux_amd64.zip -O atlantis.zip --quiet
wget https://github.com/runatlantis/atlantis/releases/download/$(curl -s https://github.com/runatlantis/atlantis/releases/latest grep "atlantis_linux_amd64.zip" | cut -d '"' -f 2 | rev | cut -d "/" -f 1 | rev)/atlantis_linux_amd64.zip -O atlantis.zip --quiet

echo "===================Installing Atlantis==================="
unzip atlantis.zip >/dev/null
chmod +x atlantis
mv atlantis /usr/local/bin/atlantis

echo "===================Importing Atlantis Config==================="
tee /tmp/atlantis_config.yaml <<EOF >/dev/null
EOF

mv /tmp/atlantis_config.yaml /usr/local/atlantis/config.yaml

echo "===================Importing Atlantis Repo Config==================="
tee /tmp/atlantis_repo.yaml <<EOF >/dev/null
${atlantis_repo_yaml}
EOF

mv /tmp/atlantis_repo.yaml /usr/local/atlantis/atlantis_repo.yaml

echo "===================Installing Atlantis as a service==================="
tee /tmp/atlantis.service <<EOF >/dev/null
[Unit]
Description=Atlantis, a tool for safely collaborating on Terraform: https://atlantis.run
[Service]
User=atlantis
ExecStart=/usr/local/bin/atlantis server --config=/usr/local/atlantis/config.yaml
Restart=always
RestartSec=3
[Install]
WantedBy=gitlab-runsvdir.target
EOF

mv /tmp/atlantis.service /etc/systemd/system/atlantis.service
chmod 600 /etc/systemd/system/atlantis.service

#https://github.com/terraform-providers/terraform-provider-aws/issues/5018 - AWS_METADATA_URL below
mkdir /etc/systemd/system/atlantis.service.d
tee /etc/systemd/system/atlantis.service.d/override.conf <<EOF >/dev/null
[Service]
Environment=AWS_METADATA_URL="http://localhost/not/existent/url"
Environment=AWS_CONFIG_FILE=/usr/local/atlantis/.aws/config
Environment=ATLANTIS_ATLANTIS_URL="https://${url}"
Environment=ATLANTIS_PORT=8888
Environment=ATLANTIS_LOG_LEVEL="info"
Environment=ATLANTIS_ALLOW_REPO_CONFIG="false"
Environment=ATLANTIS_GITLAB_USER="root"
Environment=ATLANTIS_GITLAB_WEBHOOK_SECRET='${atlantis_secret}'
Environment=ATLANTIS_GITLAB_TOKEN="$atlantis_api"
Environment=ATLANTIS_GITLAB_HOSTNAME="${url}"
Environment=ATLANTIS_REPO_WHITELIST="${url}/*"
EOF

rm -rf /root/.aws

chmod 400 /etc/systemd/system/atlantis.service.d/override.conf
chattr +i /etc/systemd/system/atlantis.service.d/override.conf
chown atlantis:atlantis -R /etc/systemd/system/atlantis.service.d
chown atlantis:atlantis -R /usr/local/atlantis


systemctl enable atlantis.service
systemctl start atlantis.service

echo "===================Done====================="
