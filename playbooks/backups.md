There are three parts:

 - **Backend infrastructure** - this repo is used as a revision control & backup system for the backend infrastructure, and can be used to redeploy the backend infra to a different server or hostname simply. Also docker images are automatically published to ghcr.io which allow for easy redeployment.
 - **Site content** - page content, along with javascript & css are backed up as database dumps nightly. This is documented below.
 - **Images** - including other uploaded files can be snapshotted on the VM management control panel, and are also copied offsite by admins.


# Backup Automation & Access

A docker container dedicated to running and accessing backups is part of backend stack.

The `backup_manager` container contains:
 - a mysql client, who's version matches the database container.
 - cronjobs to run `mysqldump`.
 - a bind mount to store backups outside of the container.
 - a bind mount to allow read-only access to `images/`.
 - sshd to allow access to retrieve backups from a non-privileged user.

### Access

Direct access to the backups via ssh is controlled by the [authorized_keys](backup_manager/pubkeys/authorized_keys).

Once the file is updated, the container needs to be redeployed to pickup the change.

```
~: ssh backupreader@app.ropewiki.com -p 22001 ls -alh backups
total 604M
drwxr-xr-x 2 backupreader backupreader 4.0K Mar  8 01:23 .
drwxr-xr-x 1 backupreader backupreader 4.0K Mar  8 06:24 ..
-rw-r--r-- 1 backupreader backupreader 201M Mar  5 10:01 all-backup-2026-03-05-100001.sql.zst
-rw-r--r-- 1 backupreader backupreader 202M Mar  6 10:00 all-backup-2026-03-06-100001.sql.zst
-rw-r--r-- 1 backupreader backupreader 202M Mar  7 10:01 all-backup-2026-03-07-100001.sql.zst
-rw-r--r-- 1 backupreader backupreader 371K Mar  7 10:01 backup.log
[...]
```


### Images

In the backup manager, the `backupreader`'s home directory has a symlink to the `images` folder which contains most
of the file-based data uploaded to the site.

An off-site backup client should connect to this container and synchronize the full content of the `images` folder to back them up.


## Offsite backups

The backup manager setup is designed to allow anyone wanting to make & copy backups to do so.

There's no official mechanism to transfer these offsite, however Coops makes nightly copies of both the database & images, storing them at home and in Backblaze B2.
