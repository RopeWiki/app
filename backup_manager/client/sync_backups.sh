#!/bin/bash

set -x

cd $(cat ~/BACKUP_VOLUME)

# Sync the images
rsync -havzP -e "ssh -p 22001" --exclude 'BALLAST_DELETE_IF_OUT_OF_SPACE' --exclude 'lost+found' backupreader@$(cat ~/BACKUP_MANAGER_HOSTNAME):~/images/ ./images

# Sync the SQL backups
rsync -havzP -e "ssh -p 22001" --delete-after backupreader@$(cat ~/BACKUP_MANAGER_HOSTNAME):~/backups/ ./backups
