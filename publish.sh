#!/bin/bash

RW_SITE_VERSION=${1:?A version like v1.0.0 must be specified for this script}
docker tag ropewiki/reverse_proxy:latest ropewiki/reverse_proxy:${RW_SITE_VERSION}
docker push ropewiki/reverse_proxy:${RW_SITE_VERSION}
docker push ropewiki/reverse_proxy:latest
docker tag ropewiki/webserver:latest ropewiki/webserver:${RW_SITE_VERSION}
docker push ropewiki/webserver:${RW_SITE_VERSION}
docker push ropewiki/webserver:latest
docker tag ropewiki/database:latest ropewiki/database:${RW_SITE_VERSION}
docker push ropewiki/database:${RW_SITE_VERSION}
docker push ropewiki/database:latest
docker tag ropewiki/backup_manager:latest ropewiki/backup_manager:${RW_SITE_VERSION}
docker push ropewiki/backup_manager:${RW_SITE_VERSION}
docker push ropewiki/backup_manager:latest
docker tag ropewiki/mailserver:latest ropewiki/mailserver:${RW_SITE_VERSION}
docker push ropewiki/mailserver:${RW_SITE_VERSION}
docker push ropewiki/mailserver:latest
echo "Remember to create and push the git tag {$RW_SITE_VERSION}"
