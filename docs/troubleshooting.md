
# Troubleshooting

## The site can't be reached after updating the webserver

Reset the containers and redeploy:

1. Tear the site down (`python3 deploy_tool.py <SITE_NAME> dc "down -v"`)
1. Bring the site back up (`python3 deploy_tool.py <SITE_NAME> start_site`)
1. Re-enable TLS (`python3 deploy_tool.py <SITE_NAME> enable_tls` then run the specified script, choosing to reinstall
   the certificate)

## Sorry! This site is experiencing technical difficulties.

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



## Refreshing TLS certificates manually

This should be performed by a cron job, but in the event of needing to do it manually,
run `python3 deploy_tool.py <SITE_NAME> renew_certs`



## Arbitrary docker compose commands

The docker-compose.yaml configuration requires a number of environment variables to be set before it can be used. To
avoid the need to set these variables yourself (apart from WG_DB_PASSWORD and RW_ROOT_DB_PASSWORD), use
`python3 deploy_tool.py <SITE_NAME> dc "<YOUR COMMAND>"`. For instance, `python3 deploy_tool.py dev dc "up -d"`.

## Updating webserver

To deploy changes to the webserver Dockerfile: `python3 deploy_tool.py redeploy webserver`

OR, manually:

1. Build the Dockerfile (`docker image build -t ropewiki/webserver .` from the root of this repo)
1. Kill and remove the webserver (`python3 deploy_tool.py <SITE_NAME> dc "rm -f -s -v ropewiki_webserver"`)
1. Restore the full deployment (`python3 deploy_tool.py <SITE_NAME> start_site`)
