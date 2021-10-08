#!/bin/bash

# https://serverfault.com/questions/725389/postfix-logs-nowhere-to-be-found-in-ubuntu-14-04-3-lts
# https://serverfault.com/a/1032591/482795
mkfifo /var/spool/postfix/public/pickup
service rsyslog start
logger -p mail.debug Test
cat /var/log/mail.log

/bin/bash
