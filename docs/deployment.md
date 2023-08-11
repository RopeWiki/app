
## Site deployment

Execute the steps below to produce a server running RopeWiki. The instructions assume an Ubuntu machine. On Windows, the
easiest option is probably to install [VirtualBox](https://www.virtualbox.org/wiki/Downloads) and host a virtual Ubuntu
system. Alternately, all of the steps after the firewall (which can be skipped) should be possible directly in a Windows
command prompt as long as [Python 3](https://www.python.org/downloads/) is installed and added to
the `PATH` (`python3 --version` to verify). Ignore all `apt` commands and instead perform the Windows alternative.

### Protect the system
If the system is exposed to the internet, apply some firewall rules.
```
# disable the firewall first, to ensure you're not locked out
ufw disable

# setup the rules
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment "host ssh"
ufw allow 80/tcp comment "proxy http"
ufw allow 443/tcp comment "proxy https"
ufw allow 22001/tcp comment "backup manager ssh"

# enable the firewall
ufw enable
```

The saved ufw rules can be see in `/etc/ufw/user(6).rules`.

### Install necessary tools

1. Update packages (`sudo apt-get update`)
1. [Install docker](https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository)
    1. Fix [this issue](https://github.com/docker/compose/issues/6931)
       with `sudo apt update && apt install rng-tools` (note: this may no longer be necessary with docker compose v2)
    1. Verify installation with `docker compose version`; result should be 2.x.x
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
# These are the manditory environment variables needed to start a copy of the site
export WG_DB_PASSWORD=<The password for the `ropewiki` DB user>
export RW_ROOT_DB_PASSWORD=<The password for the `root` DB user>
export RW_SMTP_USERNAME=<The username for logging into the smtp relay>
export RW_SMTP_PASSWORD=<The password for logging into the smtp relay>
```

### Deploy site

1. Build the necessary images: `python3 deploy_tool.py <SITE_NAME> dc build`
1. Make password variables accessible in the terminal: `source ~/rw_passwords.sh`
1. Create an empty database using `python3 deploy_tool.py <SITE_NAME> create_db`
1. Restore content into database using `python3 deploy_tool.py <SITE_NAME> restore_db`
    1. Or, for a development deployment, create a minimal database using `python3 deploy_tool.py <SITE_NAME> restore_empty_db`
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
