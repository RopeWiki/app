This container runs a postfix server as mail relay.

It doesn't really need its own custom docker image, as the upstream image is fully controlled with environment variables. However to stay in keeping with the other containers, it's rebuilt as `ropewiki/mailserver`.

Clients running inside the docker network can send mail to `ropewiki_mailserver` on port 25 to have mail relayed for them.


### Testing & Investigating

`docker logs` captures the postfix logs for easy access.

Running `mailq` inside the container shows any pending deliveries.

A simple test of the service is to trigger an email from the site (such as password reset).


#### Caveats to testing in a dev environment

- Anti-spam systems (e.g. PTR record checks, SFP records, DKIM, etc) are all designed to stop people faking the identify of a domain. As such mail sent from a dev environment (i.e. an intentionally "fake" copy of the site) will likely fail these checks and be either dropped or redirected to spam folders.

- Domestic ISPs often block outbound port tcp/25, so mail never even leave your local network if testing from home.

However note that in both of these situations the mailserver log should still show the mail coming in from the webserver, and a delivery attempt made out to the internet. This is still enough to confirm the local process is functioning (regardless of final outcome).