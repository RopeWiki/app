# backup_manager client

This folder contains tools for retrieving backups from backup_manager as a client.

## Preparation

### Install the necessary packages

```shell
sudo apt-get install rsync
```

### Set SSH key

If providing an existing SSH key:

* Copy private key in OpenSSH format to ~/.ssh/id_rsa
* `ssh-keygen -e -f ~/.ssh/id_rsa > ~/.ssh/id_rsa_com.pub`
* `ssh-keygen -i -f ~/.ssh/id_rsa_com.pub > ~/.ssh/id_rsa.pub`

### Define configuration

Define the hostname of the `app` site where backup_manager will be accessed by creating a file with this content (e.g., `ropewiki.com`)

```shell
echo "fqdn.of.backup_manager" > ~/BACKUP_MANAGER_HOSTNAME
```

Define the location of the volume where `images` and SQL `backups` should be stored (e.g., `/mnt/ropewiki_backup`)

```shell
echo "/mnt/ropewiki_backup" > ~/BACKUP_VOLUME
```

### Verify connectivity

Verify the client machine can connect to backup_manager with the following command:

```shell
ssh -p 22001 backupreader@$(cat ~/BACKUP_MANAGER_HOSTNAME)
```

### Enable access

Enable access to trusted users by copying the contents of [authorized_keys](../pubkeys/authorized_keys) to ~/.ssh/authorized_keys

### Provision automation

Copy the contents of [sync_backups.sh](./sync_backups.sh) and `chmod +x sync_backup.sh` if necessary.

Set sync_backups.sh to be run automatically by running `crontab -e` and pasting in the contents of [sync_backups.cron](./sync_backups.cron) at the end of the file (adjusting the location of sync_backups.sh if necessary).

## Operations

### Manually transfer the `images` folder:

```shell
rsync -havzP -e "ssh -p 22001" --exclude 'BALLAST_DELETE_IF_OUT_OF_SPACE' --exclude 'lost+found' backupreader@$(cat ~/BACKUP_MANAGER_HOSTNAME):~/images/ ./images
```

### Manually transfer the SQL backups:

```shell
rsync -havzP -e "ssh -p 22001" --delete-after backupreader@$(cat ~/BACKUP_MANAGER_HOSTNAME):~/backups/ ./backups
```
