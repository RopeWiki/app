# Backup manager

## Overview

The RopeWiki backup manager automatically makes periodic backups, when enabled. The backups files
follow the form `all-backup-YYYY-MM-DD-HHMMSS.sql.gz` and are stored in /home/backupreader/backups/ according
to [backup_mysql.sh](scripts/backup_mysql.sh).

The `images` data (most of the file-based data uploaded to the site) can be found in
/home/backupreader/images/ according to the mounted volume in the
[docker-compose file](../docker-compose.yaml).

The backup manager image contains:

 - a mysql client, whose version matches the database container
 - cronjobs to run `mysqldump`
 - a bind mount to store backups outside the container
 - a bind mount to allow read-only access to `images/`
 - sshd to allow access to retrieve backups from a non-privileged user

## Copying backups offsite

The database container is accessible via SSH directly at port 22001. Connect to the container using SSH via this port
and `rsync` or otherwise transfer backups. When connecting, use the username `backupreader`, and your SSH public key
must have been included in the [`authorized_keys`](pubkeys/authorized_keys) list when the database container
was built.
