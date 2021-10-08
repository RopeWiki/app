# Database

## Overview

The RopeWiki database consists of a mysql:5.5 image plus automatic periodic backups, when enabled. The backups files
follow the form `all-backup-YYYY-MM-DD.sql.gz` and are stored in /home/backupreader/backups/ according
to [backup_mysql.sh](scripts/backup_mysql.sh).

## Copying backups offsite

The database container is accessible via SSH directly at port 22001. Connect to the container using SSH via this port
and `rsync` or otherwise transfer backups. When connecting, use the username `backupreader`, and your SSH public key
must have been included in the [`authorized_keys`](../backup_pubkeys/authorized_keys) list when the database container
was built.
