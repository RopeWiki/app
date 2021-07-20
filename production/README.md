# RopeWiki server setup

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
    1. Create an empty database using `./create_db.sh`
        1. `SQL_BACKUP_FOLDER` and `IMAGES_FOLDER` must be set appropriately before running this command.
    1. Restore content into database using `./restore_db.sh <SQL BACKUP FOLDER>`
