# Ropewiki Frontend Application

## Legacy system

This section describes how to build a legacy system intended to be as similar to the currently-deployed RopeWiki site as practical to facilitate practicing restoring the database and practicing upgrades and migrations.  When complete, this system should be as similar to the server accessible at ropewiki.com as practical.

The docker-compose_legacy.yaml docker-compose file describes a full legacy system consisting primarily of a MySQL database and an nginx-php-MediaWiki webserver.

### Run a legacy system

* Build the ropewiki/webserver_legacy image
  * `docker image build -f Dockerfile_legacy -t ropewiki/legacy_webserver .`
* [Optional] Open an interactive shell to view files and run test commands in webserver
  * `docker container run -it ropewiki/legacy_webserver /bin/bash`
* Place a database *.sql backup file in ./mysql/backup
* **TODO**: document how to mount images folder
* Set the password to use for the ropewiki user in the restored database by editing docker-compose_legacy.yaml and changing WG_DB_PASSWORD to the appropriate password
* Bring up the system with docker-compose
  * `docker-compose -f docker-compose_legacy.yaml -p rwlegacy up`
* [Optional] Explore the database with adminer
  * Navigate to http://localhost:8081 in a browser
  * Log in with
    * System: MySQL
    * Server: ropewiki_legacy_db
    * Username: root
    * Password: ropewikilegacydatabasepassword (or whatever is set; see configuration in docker-compose_legacy.yaml)
    * Database: (leave this box blank)
* Open an interactive shell in the MySQL container
  * `docker container exec -it rwlegacy_ropewiki_legacy_db_1 /bin/bash`
  * Create an empty database to be filled with the backup
    * `mysqladmin -u root -p create ropewiki`
      * See the password listed in the "Explore the database with adminer" section above
  * Restore backup into empty database
    * `mysql -u root -p ropewiki < /root/backup/all-backup-2020-06-12.sql`
      * See the password listed in the "Explore the database with adminer" section above
      * Note: replace all-backup-2020-06-12.sql with the name of your backup file
      * Note: this operation will take a few minutes with no visual feedback
      * Note: When this operation is complete, the database list in adminer may not update properly.  To force an update, create a new empty database (and then drop it).
  * Exit the shell in the MySQL container
    * `exit`
* Shut down the system
  * CTRL-c / CMD-C
* Restart the system
  * `docker-compose -f docker-compose_legacy.yaml -p rwlegacy up`
* [Optional] Delete the system
  * `docker-compose -f docker-compose_legacy.yaml -p rwlegacy down`
    * Note that this will disconnect the docker volume automatically created for the mysql container from any container (leaving it dangling).  If you have restored the database, this will leave a very large volume dangling
    * [Optional] See your dangling volumes and their space
      * `docker system df -v`
    * [Optional] Delete your dangling volumes to free disk space
      * ``docker volume rm `docker volume ls -q -f dangling=true` ``

### Exploring / troubleshooting a legacy system

* Print webserver stdout + stderr (there should not be much here)
  * `docker container logs rwlegacy_ropewiki_legacy_webserver_1`
* Run an interactive shell inside the webserver
  * `docker container exec -it rwlegacy_ropewiki_legacy_webserver_1 /bin/bash`
  * Print normal access log
    * `cat /var/log/nginx/access.log`
  * Print error log
    * `cat /var/log/nginx/error.log`