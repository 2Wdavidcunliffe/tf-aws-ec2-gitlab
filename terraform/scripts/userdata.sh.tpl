#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y curl openssh-server ca-certificates debconf-doc python-pip
debconf-set-selections <<< "postfix postfix/mailname string ${url}"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install --assume-yes postfix
export DEBIAN_FRONTEND=dialog

pip install awscli

curl -s https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | bash
EXTERNAL_URL="https://${url}" apt-get install -y gitlab-ce

cp /tmp/gitlab.rb /etc/gitlab/gitlab.rb
gitlab-ctl reconfigure
gitlab-ctl restart

# Setup Backup Cron set for 2am
crontab -l | { cat; echo "0 2 * * * /opt/gitlab/bin/gitlab-backup create CRON=1"; } | crontab -
crontab -l | { cat; echo "0 2 * * * aws s3 cp /etc/gitlab/$(date +%s)-gitlab-secrets.json s3://gitlab.2wdc.net/"; } | crontab -
crontab -l | { cat; echo "0 2 * * * aws s3 cp /etc/gitlab/$(date +%s)-gitlab.rb s3://gitlab.2wdc.net/"; } | crontab -

# Restore latest backup to gitlab