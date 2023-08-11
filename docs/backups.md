# Backups

## Overview

There are three key sources of data for ropewiki:

1. **Code**. The underlying code is deployed via github & and snapshotted into versioned docker images pushed up to dockerhub. This allows us to restore the "last known good" version of the site if we run into problems (caviet: the site versions needs to match the database schema).
2. **Database**. This is the source of most of the content you see on the site. However Mediawiki stores more than just page information in the database. Things like javascript and css also get served from the database.
3. **Images**. This refers to anything uploaded to the site (photos, pdfs, etc). These are stored as regular files on disk.


## Automatic backups

A dedicated backup-manager container is responsible for taking nightly backups of the database. The backups files follow the form `all-backup-YYYY-MM-DD-HHMMSS.sql.gz` and are stored in `/home/backupreader/backups`` according to [backup_mysql.sh](scripts/backup_mysql.sh).

Dedicated SSH access is provided to the backup manager (on port 22001) for
the `backupreader` user. People who'd like access to the backups should add their public ssh key to the [authorized_keys](backup_manager/pubkeys/authorized_keys) file. (The container then needs to be redeployed).

The backup-manager also has access to a read-only copy of images, allowing an external client to make offsite backups of both the database and the images.

Currently @hcooper is taking offsite backups, which are also shipped to b2 backblaze.