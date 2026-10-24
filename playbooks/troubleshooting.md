

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
