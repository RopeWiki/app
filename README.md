# Ropewiki Infrastructure

This repository houses the code to deploy the core services which power `ropewiki.com`.

### How does ropewiki work?

Ropewiki is built on [Mediawiki](https://www.mediawiki.org/wiki/MediaWiki), the same software which powers Wikipedia. An extension called [Semantic Mediawiki](https://www.semantic-mediawiki.org/wiki/Semantic_MediaWiki) is used to add meaningful connection between different types of pages (e.g. region -> canyon -> report).

Underneath it's a regular PHP, MySQL & Nginx stack.

The stack is deployed as 5 docker containers, each with their own set of docs:
  - [backup manager](docs/backups.md)
  - [database](docs/database.md)
  - [mailserver](docs/mailserver.md)
  - [reverse proxy](docs/reverse_proxy.md)
  - [webserver](docs/webserver.md)


### How is ropewiki deployed?

The containers are deployed using custom tooling, `deploy_tool.py`, which abstracts away a lot of behind the scenes work. Underneath it uses `docker-compose`. For more information see the [Deployment docs](docs/deployment.md).


### How do I develop ropewiki?

Ropewiki is designed to be re-deployable for easy <sup>(citation needed)</sup> testing and development. An empty copy of the site can be deployed using this repository. More details on developing the site can be found in the [Development docs](docs/development.md).


### Troubleshooting

For a collection of other helpful documention, see [Troubleshooting docs](docs/troubleshooting.md).
