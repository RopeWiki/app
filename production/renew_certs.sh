#!/bin/bash
echo === `date` ===
docker-compose exec ropewiki_reverse_proxy certbot renew
echo
