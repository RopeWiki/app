# RopeWiki server setup

## Site deployment
Execute the following steps to produce a server running RopeWiki starting from a machine running Ubuntu.

1. Protect the system
    1. Setup firewall from scratch
        1. Block everything incoming (`sudo ufw default deny incoming`)
        1. Allow everything outgoing (`sudo ufw default allow outgoing`)
        1. Allow SSH (`sudo ufw allow OpenSSH`)
        1. Allow web server requests (`sudo ufw allow 80/tcp && ufw allow 443/tcp`)
        1. Optionally, allow debugging: (`sudo ufw allow 8080/tcp)
    1. Alternately, setup firewall by importing rules
        1. Copy `/etc/ufw/user.rules`
        1. Copy `/etc/ufw/user6.rules`
    1. Enable firewall (`sudo ufw enable`)
1. Install necessary tools
    1. Update packages (`sudo apt-get update`)
    1. [Install docker](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
    1. [Install docker-compose](https://docs.docker.com/compose/install/#install-compose-on-linux-systems)
        1. Fix [this issue](https://github.com/docker/compose/issues/6931) with `sudo apt update && apt install rng-tools`
    1. Install git (`sudo apt-get install git`)
    1. Clone this repository into an appropriate folder (perhaps `/rw`)
1. Transfer site data
    1. Create a folder that will hold persistent mount data (perhaps `/rw/mount`)
    1. Get latest SQL backup
        1. Create a subfolder in the persistent mount data folder that will hold SQL backups (perhaps `/rw/mount/sqlbackup`)
            1. If transferring from an old server, run `get_sql_backup.sh <SQL BACKUP FOLDER>` (e.g., `get_sql_backup.sh /rw/mount/sqlbackup`)
    1. Get `images` folder
        1. If transferring from an old server, run `get_images.sh <ROPEWIKI MOUNT FOLDER>` (e.g., `get_images.sh /rw/mount`)
1. Deploy site
    1. Build `ropewiki/legacy_webserver` image according to [the instructions](README.md#Run a legacy server)
    1. Build `ropewiki/reverse_proxy` image by running the command specified in the [Dockerfile](reverse_proxy/Dockerfile)
    1. Ensure environment variables are all populated correctly; example:
       ```shell
       export WG_DB_PASSWORD=whateveryourpasswordis
       export WG_HOSTNAME=ropewiki.com
       export WG_PROTOCOL=https
       export SQL_BACKUP_FOLDER=/rw/mount/sqlbackup
       export IMAGES_FOLDER=/rw/mount/images
       export PROXY_CONFIG_FOLDER=/rw/mount/proxy_config
       ```
    1. Create an empty database using `./create_db.sh`
        1. `SQL_BACKUP_FOLDER` and `IMAGES_FOLDER` environment variables must be set appropriately before running this command.
    1. Restore content into database using `./restore_db.sh ${SQL_BACKUP_FOLDER}`
    1. Bring site up with `./start_prod.sh`
    1. (Optional) Confirm that the webserver container is working, apart from the reverse proxy, by visiting `http://<hostname>:8080`
    1. Confirm that the site is working via HTTP by visiting `http://<hostname>`
    1. Enable TLS with `./enable_tls.sh`
        1. Note that this should only ever be run once unless the `${PROXY_CONFIG_FOLDER}/letsencrypt` folder is deleted
        1. Enable redirection (option 2) when prompted
        1. Verify success by visiting https://<hostname>
    1. Create cronjob to automatically update certificates
        1. From this working directory, run:
            ```
            crontab -l | { cat; echo "0 */12 * * * $PWD/renew_certs.sh >> ${PROXY_CONFIG_FOLDER}/cert_renewals.log 2>&1"; } | crontab -
            ```
        1. To edit or delete crontabs, `crontab -e`

## Site maintenance
### Refreshing TLS certificates manually
This should be performed by a cron job, but in the event of needing to do it
manually, run `./renew_certs.sh`
