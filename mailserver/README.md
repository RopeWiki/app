This container runs a postfix server as mail relay.

It doesn't really need its own custom docker image, as the upstream image is fully controlled with environment variables. However to stay in keeping with the other containers, it's rebuilt as `ropewiki/mailserver`.

Clients running inside the docker network can send mail to `ropewiki_mailserver` on port 25 to have mail relayed for them.

`docker logs` captures the postfix logs, and running `mailq` inside the container shows any pending deliveries.

TODO:
 - fix PTR record
 - add SFP record
 - setup Domain Keys