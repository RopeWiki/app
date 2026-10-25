# Site maintenance

Note: all the operations below assume the commands are executed on the shell of the deployed server.

## Refreshing TLS certificates manually

This should be performed by a cron job, but in the event of needing to do it manually,
run `python3 deploy_tool.py <SITE_NAME> renew_certs`

Also see the TLS support note in [the deployment documentation](deployment.md#tls-support).

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
