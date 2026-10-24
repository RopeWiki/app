# Backups

## Scope

There are three parts that make up a RopeWiki deployment:

 - **Backend infrastructure** - this repo is used as a revision control & backup system for the backend infrastructure, and can be used to redeploy the backend infra to a different server or hostname simply. Also docker images are automatically published to ghcr.io which allow for easy redeployment.
 - **Site content** - page content, along with javascript & css are backed up as database dumps nightly. This is documented below.
 - **Images** - including other uploaded files can be snapshotted on the VM management control panel, and are also copied offsite by admins.

This page documents operations involving the site content (database) and images (all files in images folder, not just images).

## Automation & Access

A [`backup_manager`](../backup_manager) docker container dedicated to creating and accessing backups is part of backend stack.

### Access

Direct access to the backups via ssh is controlled by the [authorized_keys](../backup_manager/pubkeys/authorized_keys).

Once the file is updated, the `backup_manager` container needs to be redeployed to pick up the change.

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

The backup manager setup is designed to allow multiple people to make and store backups.

There's no official mechanism to transfer these offsite, however Coops makes nightly copies of both the database & images, storing them at home and in Backblaze B2.
