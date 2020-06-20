# Ropewiki Frontend Application

## Legacy system

This section describes how to build a legacy system intended to be as similar to the currently-deployed RopeWiki site as practical to facilitate practicing restoring the database and practicing upgrades and migrations.  When complete, this system should be as similar to the server accessible at ropewiki.com as practical.

### Prerequisites

To complete these instructions, you must have:
* [Docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/install/) installed
* A backup of the site database in .sql format (1.2+ GB)
* The `images` folder of the site (18.3+ GB)

Although these instructions should work on any Docker-equipped system, they have only been tested on Ubuntu 18.04.

### Run a legacy system

* Build the ropewiki/webserver_legacy image
  * `docker image build -f Dockerfile_legacy -t ropewiki/legacy_webserver .`
* [Optional] Open an interactive shell to view files and run test commands in webserver
  * `docker container run -it ropewiki/legacy_webserver /bin/bash`
* Place a database *.sql backup file in ./mysql/backup
* Place images folder (or symlink) in ./html/ropewiki/images
  * To create a symlink from the root of this repo: `ln -s /path/to/images ./html/ropewiki/images`
* Set the password to use for the ropewiki user in the restored database by editing docker-compose_legacy.yaml and changing WG_DB_PASSWORD and MYSQL_ROOT_PASSWORD to the appropriate password for the database you will be restoring
* Bring up the system with docker-compose
  * `docker-compose -f docker-compose_legacy.yaml -p rwlegacy up`
* [Optional] Explore the database with adminer
  * Navigate to http://localhost:8081 in a browser
  * Log in with
    * System: MySQL
    * Server: ropewiki_legacy_db
    * Username: root
    * Password: (whatever is set in docker-compose_legacy.yaml)
    * Database: (leave this box blank)
* Open an interactive shell in the MySQL container
  * `docker container exec -it rwlegacy_ropewiki_legacy_db_1 /bin/bash`
  * Create an empty database to be filled with the backup
    * `mysqladmin -u root -p create ropewiki`
      * The password is whatever is set in docker-compose_legacy.yaml for MYSQL_ROOT_PASSWORD
  * Restore backup into empty database
    * `mysql -u root -p ropewiki < /root/backup/all-backup-2020-06-12.sql`
      * The password is whatever is set in docker-compose_legacy.yaml for MYSQL_ROOT_PASSWORD
      * Note: replace all-backup-2020-06-12.sql with the name of your backup file
      * Note: this operation will take a few minutes with no visual feedback
  * [Optional] View database content in adminer
    * Note: When the above operation is complete, the database list in adminer may not update properly.  To force an update, create a new empty database (and then drop it).
  * Exit the shell in the MySQL container
    * `exit`
* [Optional] Shut down the system
  * CTRL-c / CMD-C
* [Optional] Restart the system
  * `docker-compose -f docker-compose_legacy.yaml -p rwlegacy up`
* Your site is now set up; visit http://localhost:8080 to see it!
* [Optional] Delete the system
  * `docker-compose -f docker-compose_legacy.yaml -p rwlegacy down`
    * Note that this will disconnect the docker volume automatically created for the mysql container from any container (leaving it dangling).  If you have restored the database, this will leave a very large volume dangling
    * [Optional] See your dangling volumes and their space
      * `docker system df -v`
    * [Optional] Delete your dangling volumes to free disk space
      * ``docker volume rm `docker volume ls -q -f dangling=true` ``

### Troubleshooting running a legacy system

* Sorry! This site is experiencing technical difficulties.
  * If this is accompanied by "(Cannot contact the database server)", it means the MediaWiki app (the ropewiki_legacy_webserver container) is not configured properly to contact the database (the ropewiki_legacy_db container).  The most likely problem is that you have not changed WG_DB_PASSWORD to match the one in the database backup you restored.  This password should be changed in docker-compose_legacy.yaml to match the password used in the database you restored; see instructions above.

### Exploring a legacy system

* Print webserver stdout + stderr (there should not be much here)
  * `docker container logs rwlegacy_ropewiki_legacy_webserver_1`
* Run an interactive shell inside the webserver
  * `docker container exec -it rwlegacy_ropewiki_legacy_webserver_1 /bin/bash`
  * Print normal access log
    * `cat /var/log/nginx/access.log`
  * Print error log
    * `cat /var/log/nginx/error.log`

## Mirror server

This repository includes scripts for mirroring the production legacy webserver to a local development instance.  `init_mirror_server.sh` creates a new database container and volume intended for use in the development instance (after removing any previous container or volume created by prior runs of the script).  `refresh_mirror_server.sh` retrieves the most recent database backup from the production server and synchronizes any new content in the /images folder, but these operations require public key access to the production servers.  This latter script is intended to be run as a nightly cronjob.

