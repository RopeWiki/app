The following instructions assume an Ubuntu based OS, running on either a server, virtual machine, or WSL instance.

The starting point is a vanilla Ubuntu environment, and the end goal is a locally running copy of ropewiki.

### Firewall the system

If the system is not externally accessible, this step can be skipped.

As root (e.g. `sudo -s`) run:

```bash
ufw default deny incoming  # Block everything incoming
ufw default allow outgoing  # Allow everything outgoing
ufw allow OpenSSH  # Allow SSH to host machine
ufw allow 80/tcp  # Allow http
ufw allow 443/tcp  # Allow https
ufw allow 22001/tcp  # Allow SSH directly to backup containers
ufw allow 8080/tcp  # Optionally, direct debugging of webserver
ufw enable  # Enable firewall
```
---

### Install Prerequisites Tools

``` bash
# Basic tools
apt install python3 git rsync zstd
```

Follow the appropriate instructions for installing docker, e.g. [for Ubuntu](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository).

Clone this repo to somewhere convenient.  Standard server deployments use `/rw/app`.

```bash
cd /
mkdir ./rw
git clone https://github.com/RopeWiki/app.git ./rw/app
```

---
### Create a Site Config

For each deployment of RopeWiki there are a number of settings which are defined in a `site_config` file. These are specific to the site (e.g. domain name, directory locations, etc) but importantly do not include secrets (e.g. passwords, keys, etc).

The name of the file will be used as part of the naming scheme of the containers, e.g. `dev` will become `dev-ropewiki_webserver-1`, and also provided as a parameter to the `deploy_tool.py` command later on.

Copy or modify an existing config, e.g. [dev.json](site_configs/dev.json) and modify it to suit your needs.

A standard location to keep all the external RopeWiki data is helpful (logs, images, etc), and `./rw/mount` will be assumed as this path for the rest of the instructions.

```
./rw/app
./rw/mount/images
./rw/mount/sqlbackup
[...]
```

---

### Transfer site data

To restore the production site, you will require access to the backups, [documented here](https://github.com/RopeWiki/app/wiki/Backups), which can be arranged by an existing admin for you.

#### Database restore
The database can be automatically restored from a compressed `.sql` file.

```bash
# Figure out which is the newest backup.
FILE=$(ssh backupreader@app.ropewiki.com -p 22001 ls backups | grep all-backup | sort | tail -n 1)

# Copy it locally
rsync -avz -e "ssh -p 22001" backupreader@app.ropewiki.com:backups/$FILE ./rw/mount/sql_backup_folder
```

#### Images restore
```bash
# Copy all images across (Note: this is over 70GB!).
rsync -avz --exclude='BALLAST_DELETE_IF_OUT_OF_SPACE' -e "ssh -p 22001" backupreader@app.ropewiki.com:images/* ./rw/mount/images/
```

---

### Mandatory Secrets
There are four environment values which need to be set for the RopeWiki deployment system to work.

It's helpful to create a small password script (e.g. `~/rw_passwords.sh`) to save them. They should not be checked into the repo.

```bash
#!/bin/bash
# These two can be custom when creating a new database, but must
# be set to the production values after a database restore.
export WG_DB_PASSWORD=<The password for the `ropewiki` DB user>
export RW_ROOT_DB_PASSWORD=<The password for the `root` DB user>

# These two need to be defined, but in a developer deployment use
# fake values to stop users receiving notifications.
export RW_SMTP_USERNAME=<The username for logging into the smtp relay>
export RW_SMTP_PASSWORD=<The password for logging into the smtp relay>
```

---

### Starting the site

The `deploy_tool.py` command is used for nearly all management of the RopeWiki containers. It provides environment variables management, ensuring secrets aren't stored persistently in our docker images.

```bash
# $SITE_NAME is the name of your `site_configs` file.

# Ensure the required secret variables are defined:
source ~/rw_passwords.sh

# Build the docker containers (fyi, `dc` refers to `docker compose`)
# TODO: Talk about how ghcr.io images can now be used to avoid rebuilding locally
./deploy_tool.py $SITE_NAME dc build

# Initialize the database configuration
./deploy_tool.py $SITE_NAME create_db

# Restore the production database. (This will automatically find the
# newest backup file in your `sql_backup_folder` folder.
./deploy_tool.py $SITE_NAME restore_db

# ALTERNATIVELY: restore an absolutely minimal mediawiki database. This is
# useful for testing changes to the infrastructure which don't require site data.
./deploy_tool.py $SITE_NAME restore_empty_db

# Start all the containers
./deploy_tool.py $SITE_NAME start_site
```
***

### Testing

If everything has started successfully the site should be reachable via `http://$hostname/`.

If the containers are all running (`docker ps -a`) but something doesn't work, the first things to check are the protocol and hostname. They both form part of the webserver's initial redirect.

```bash
# Requests without a page name should get redirected to "Main Page".
$ curl -v http://localhost 2>&1 | grep -i location
< location: http://localhost/Main_Page

# Try requesting http://localhost/Main_Page directly and compare the results.
```

***

### TLS Support

Production reliably deploys and renews TLS certifications using a weekly cron job:

```
docker compose -p prod exec ropewiki_reverse_proxy certbot --nginx --non-interactive -d ropewiki.com -d www.ropewiki.com -d tiles.ropewiki.com
```

However the method for generic development instances is broken (it doesn't automatically renewal, requires human input, and has inflexible subdomain support). The old instructions are kept here for when future improvement happens:

1. Enable TLS with `python3 deploy_tool.py <SITE_NAME> enable_tls`
    1. Note that the certs should be persisted in `${proxy_config_folder}/letsencrypt`; select option 1 to reinstall the
       existing cert if prompted
    1. Enable redirection (option 2) when prompted
    1. Verify success by visiting `https://<hostname>`
    1. Create cronjob to automatically update certificates
        1. From this working directory, run `python3 deploy_tool.py <SITE_NAME> add_cert_cronjob`
        1. To edit or delete crontabs, `crontab -e`
