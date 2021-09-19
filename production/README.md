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
1. Define site to be deployed
    1. Ensure that there is a .json file in [site_configs](site_configs) corresponding to the site to be deployed
    1. Create a new .json file, modeled after [example.json](site_configs/example.json), if necessary
        1. Create a folder that will hold persistent mount (perhaps `/rw/mount`) and define folders relative to that folder
    1. SITE_NAME is the name of the .json file without extension (e.g., example.json implies a SITE_NAME of `example`)
1. Transfer site data
    1. Get latest SQL backup
        1. If transferring from an old server, run `python3 deploy_tool.py <SITE_NAME> get_sql_backup_legacy`
    1. Get `images` folder
        1. If transferring from an old server, run `python3 deploy_tool.py <SITE_NAME> get_images_legacy`
1. Deploy site
    1. Build `ropewiki/webserver` image from the root of this repo: `docker image build -t ropewiki/webserver .`
    1. Build `ropewiki/reverse_proxy` image by running the command specified in the [Dockerfile](reverse_proxy/Dockerfile)
    1. Ensure environment variable for DB password is populated correctly; example: `export RW_DB_PASSWORD=whateveryourpasswordis`
    1. Create an empty database using `python3 deploy_tool.py <SITE_NAME> create_db`
    1. Restore content into database using `python3 deploy_tool.py <SITE_NAME> restore_db`
    1. Bring site up with `python3 deploy_tool.py <SITE_NAME> start_site`
    1. (Optional) Confirm that the webserver container is working, apart from the reverse proxy, by visiting `http://<hostname>:8080`
    1. Confirm that the site is working via HTTP by visiting `http://<hostname>`
    1. Enable TLS with `python3 deploy_tool.py <SITE_NAME> enable_tls`
        1. Note that the certs should be persisted in `${proxy_config_folder}/letsencrypt`; select option 1 to reinstall the existing cert if prompted
        1. Enable redirection (option 2) when prompted
        1. Verify success by visiting https://<hostname>
    1. Create cronjob to automatically update certificates
        1. From this working directory, run `python3 deploy_tool.py <SITE_NAME> add_cert_cronjob`
        1. To edit or delete crontabs, `crontab -e`

## Site maintenance
### Refreshing TLS certificates manually
This should be performed by a cron job, but in the event of needing to do it
manually, run `python3 deploy_tool.py <SITE_NAME> renew_certs`

### Arbitrary docker-compose commands
The docker-compose.yaml configuration requires a number of environment variables to be set before it can be used.  To
avoid the need to set these variables yourself (apart from WG_DB_PASSWORD), use
`python3 deploy_tool.py <SITE_NAME> dc "<YOUR COMMAND>"`.  For instance, `python3 deploy_tool.py dev dc "up -d"`.

### Updating webserver
To deploy changes to the webserver Dockerfile:

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
