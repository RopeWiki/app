# RopeWiki server

## Introduction

This repository contains the information necessary to deploy the RopeWiki technical infrastructure (though it does not
contain the database content nor the `images` folder content of the real site).

### Site architecture

* The [MySQL database](database/README.md) stores all the non-file site data
* The [webserver](webserver/README.md) runs MediaWiki with extensions, and also stores all the file-based site
  data/uploads
    * Exposes port 8080 for direct access to the webserver that bypasses the reverse proxy
* The [reverse proxy](reverse_proxy/README.md) manages TLS termination and also redirects according to target site
    * Exposes ports 80 & 443 as the external-facing webserver
* The [backup manager](backup_manager/README.md) exposes site data for backup
    * Exposes port 22001 for SSH access to [`backupreader`](backup_manager/pubkeys/README.md) users

## Site deployment

Execute the steps below to produce a server running RopeWiki. The instructions assume an Ubuntu machine. On Windows, the
easiest option is probably to install [VirtualBox](https://www.virtualbox.org/wiki/Downloads) and host a virtual Ubuntu
system. Alternately, all of the steps after the firewall (which can be skipped) should be possible directly in a Windows
command prompt as long as [Python 3](https://www.python.org/downloads/) is installed and added to
the `PATH` (`python3 --version` to verify). Ignore all `apt` commands and instead perform the Windows alternative.

### Protect the system

1. Setup firewall from scratch
    1. Block everything incoming (`sudo ufw default deny incoming`)
    1. Allow everything outgoing (`sudo ufw default allow outgoing`)
    1. Allow SSH to host machine (`sudo ufw allow OpenSSH`)
    1. Allow web server requests (`sudo ufw allow 80/tcp && ufw allow 443/tcp`)
    1. Allow SSH directly to containers (`sudo ufw allow 22001/tcp && ufw allow 22002/tcp`)
    1. Optionally, allow debugging: (`sudo ufw allow 8080/tcp`)
1. Alternately, setup firewall by importing rules
    1. Copy `/etc/ufw/user.rules`
    1. Copy `/etc/ufw/user6.rules`
1. Enable firewall (`sudo ufw enable`)

### Install necessary tools

1. Update packages (`sudo apt-get update`)
1. [Install docker](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
1. [Install legacy/v1 docker-compose](https://docs.docker.com/compose/install/#install-compose-on-linux-systems) with `sudo apt install docker-compose`
    1. Fix [this issue](https://github.com/docker/compose/issues/6931)
       with `sudo apt update && apt install rng-tools`
    1. Verify installation with `docker-compose --version`; result should be 1.29.2 or similar, not 2.x.x
1. Install git (`sudo apt-get install git`)
1. Clone this repository into an appropriate folder (perhaps `/rw`)

### Define site to be deployed

1. Ensure that there is a .json file in [site_configs](site_configs) corresponding to the site to be deployed
1. Create a new .json file, modeled after [dev.json](site_configs/dev.json), if necessary
    1. Create a folder that will hold persistent mount data (perhaps `/rw/mount`) and define folders relative to that
       folder
1. SITE_NAME is the name of the .json file without extension (e.g., example.json implies a SITE_NAME of `example`)

### Transfer site data

1. Get latest SQL backup
    1. If transferring from an old server, run `python3 deploy_tool.py <SITE_NAME> get_sql_backup_legacy`
1. Get `images` folder
    1. If transferring from an old server, run `python3 deploy_tool.py <SITE_NAME> get_images_legacy`
1. Create a shortcut to declare passwords: create `~/rw_passwords.sh` (or another location) with content like:
```shell
#!/bin/bash

export WG_DB_PASSWORD=<The password for the `ropewiki` DB user>
export RW_ROOT_DB_PASSWORD=<The password for the `root` DB user>
```

### Deploy site

1. Build the necessary images: `python3 deploy_tool.py <SITE_NAME> dc build`
1. Make password variables accessible in the terminal: `source ~/rw_passwords.sh`
1. Create an empty database using `python3 deploy_tool.py <SITE_NAME> create_db`
1. Restore content into database using `python3 deploy_tool.py <SITE_NAME> restore_db`
    1. Or, for a development deployment, create a minimal database using `python3 deploy_tool.py <SITE_NAME> restore_schema`
1. Bring site up with `python3 deploy_tool.py <SITE_NAME> start_site`
1. (Optional) Confirm that the webserver container is working, apart from the reverse proxy, by
   visiting `http://<hostname>:8080`
1. Confirm that the site is working via HTTP by visiting `http://<hostname>`
1. Enable TLS with `python3 deploy_tool.py <SITE_NAME> enable_tls`
    1. Note that the certs should be persisted in `${proxy_config_folder}/letsencrypt`; select option 1 to reinstall the
       existing cert if prompted
    1. Enable redirection (option 2) when prompted
    1. Verify success by visiting `https://<hostname>`
    1. Create cronjob to automatically update certificates
        1. From this working directory, run `python3 deploy_tool.py <SITE_NAME> add_cert_cronjob`
        1. To edit or delete crontabs, `crontab -e`

## Backups

Direct SSH access is provided to the backup manager at port 22001 for
the `backupreader` user for clients who possess the private key to any of the public keys listed
in [authorized_keys](backup_manager/pubkeys/authorized_keys).

### Database

In the backup manager, the `backupreader`'s home directory has a `backups` folder where complete backups of the database
will be created daily and named `all-backup-YYYY-MM-DD-FFFFFF.tar.gz`. An off-site backup client should connect to this
container and copy the latest `all-backup` file to back up the database.

### Images

In the backup manager, the `backupreader`'s home directory has a symlink to the `images` folder which contains most
of the file-based data uploaded to the site. An off-site backup client should connect to this container and
synchronize the full content of the `images` folder to back them up.

## Site maintenance

### Refreshing TLS certificates manually

This should be performed by a cron job, but in the event of needing to do it manually,
run `python3 deploy_tool.py <SITE_NAME> renew_certs`

### Arbitrary docker-compose commands

The docker-compose.yaml configuration requires a number of environment variables to be set before it can be used. To
avoid the need to set these variables yourself (apart from WG_DB_PASSWORD and RW_ROOT_DB_PASSWORD), use
`python3 deploy_tool.py <SITE_NAME> dc "<YOUR COMMAND>"`. For instance, `python3 deploy_tool.py dev dc "up -d"`.

### Updating webserver

To deploy changes to the webserver Dockerfile: `python3 deploy_tool.py redeploy webserver`

OR, manually:

1. Build the Dockerfile (`docker image build -t ropewiki/webserver .` from the root of this repo)
1. Kill and remove the webserver (`python3 deploy_tool.py <SITE_NAME> dc "rm -f -s -v ropewiki_webserver"`)
1. Restore the full deployment (`python3 deploy_tool.py <SITE_NAME> start_site`)

## Troubleshooting

### The site can't be reached after updating the webserver

Reset the containers and redeploy:

1. Tear the site down (`python3 deploy_tool.py <SITE_NAME> dc "down -v"`)
1. Bring the site back up (`python3 deploy_tool.py <SITE_NAME> start_site`)
1. Re-enable TLS (`python3 deploy_tool.py <SITE_NAME> enable_tls` then run the specified script, choosing to reinstall
   the certificate)

### Sorry! This site is experiencing technical difficulties.

If this is accompanied by "(Cannot contact the database server)", it means the MediaWiki app (the ropewiki_webserver
container) is not configured properly to contact the database (the ropewiki_db container). The most likely problem is
that you have not specified the WG_DB_PASSWORD environment variable to match the one in the database backup you
restored. WG_DB_PASSWORD should be specified to match the password used in the database you restored; see instructions
above.

To verify whether a connection with a particular username and password can be established, open a terminal in the
database container: `docker container exec -it dev_ropewiki_db_1 /bin/bash` (but with an appropriate
container; `python3 deploy_tool.py <SITE_NAME> dc ps` to list containers). Then, attempt to connect to the database
with `mysql -u <USERNAME> -p<PASSWORD`. If successful, check users with `select host, user, password from mysql.user;`.

If the above is successful, verify that the connection can be made from the webserver container by opening a terminal in
the webserver container via a similar process as above. Add the hostname to the `mysql` command
like: `mysql -h ropewiki_db -u <USERNAME> -p<PASSWORD>`.

## Running a local development instance

These instructions can be used to run a local development instance with just a few adjustments. Simply make sure there
is a site_config appropriate to your local machine, and otherwise follow the instructions above normally. The
site_config "`local`" is excluded from git tracking, so it is an ideal place to define a system configuration that other
people are unlikely to use. However, if your local development instance setup is likely to be reusable by others, feel
free to add it to site_configs; a `local_windows.json` site_config would probably be helpful to others, for instance.

Note that, in all cases, the following resources (not included in this repo) are necessary to bring up a functional
site:

* A backup of the site database in .sql format (1.2+ GB)
* The `images` folder of the site (18.3+ GB)

TLS is not necessary, and sometimes not feasible, on a local development instance. In that case, simply don't enable TLS
and instead access the site with `http`. If the site_config `hostname` is `localhost`, then port 80 will be used and the
site should be accessible at `http://localhost`. To use a different port, specify, e.g., a `hostname`
of `localhost:8081` making the site available at `http://localhost:8081`. Do not use port 8080 because it is already
used to provide debug access directly to the webserver without going through the reverse_proxy.

### Exploring the system

_The commands below assume the use of the `local` SITE_NAME/site_config; change the commands to reflect your site
configuration name if necessary._

* Print webserver stdout + stderr (there should not be much here)
    * `python3 deploy_tool.py local dc logs ropewiki_webserver`
* Run an interactive shell inside the webserver
    * Determine the name of the webserver container with `python3 deploy_tool.py local dc ps`
    * `docker container exec -it local_ropewiki_webserver_1 /bin/bash` (but substitute your webserver container name)
    * Print normal access log
        * `cat /var/log/nginx/access.log`
    * Print error log
        * `cat /var/log/nginx/error.log`
* Delete the system
    * `python3 deploy_tool.py local dc down`
        * Note that this will disconnect the docker volume automatically created for the mysql container from any
          container (leaving it dangling). If you have restored the database, this will leave a very large volume
          dangling
        * See your dangling volumes and their space
            * `docker system df -v`
        * Delete your dangling volumes to free disk space
            * ``docker volume rm `docker volume ls -q -f dangling=true` ``
