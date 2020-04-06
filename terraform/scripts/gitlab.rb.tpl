external_url '${url}'
gitlab_rails['gitlab_ssh_host'] = 'ssh.2wdc.net'
gitlab_rails['manage_backup_path'] = ${manage_backup_path}
gitlab_rails['backup_path'] = "${backup_path}"
gitlab_rails['backup_keep_time'] = 604800
gitlab_rails['backup_upload_connection'] = {
  'provider' => 'AWS',
  'region' => '${region}',
	'use_iam_profile' => 'true'
}
gitlab_rails['backup_upload_remote_directory'] = '${backup_upload_remote_directory}'
gitlab_rails['backup_multipart_chunk_size'] = 104857600
