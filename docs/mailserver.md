This container runs a postfix server as mail relay.

It doesn't really need its own custom docker image, as the upstream image is fully controlled with environment variables. However to stay in keeping with the other containers, it's rebuilt as `ropewiki/mailserver`.

Clients running inside the docker network can send mail to `ropewiki_mailserver` on port 25 to have mail relayed for them.

### Deployment

By default it routes mail via gmail's smtp relay, and requires providing two environment variables:

```
    $RW_SMTP_USERNAME
    $RW_SMTP_PASSWORD
```

These can be your own personal credentials for testing ([setup guide](https://www.gmass.co/blog/gmail-smtp/)), or the real credentials for `ropewiki@gmail.com`.

If you want to relay mail via a different provider (e.g. your hosting provider requires you to use theirs), you can additionally set:

```
    $RW_SMTP_HOST
    $RW_SMTP_PORT
```

### Testing & Investigating

Useful commands inside the mailserver container:
- `tail -f /var/log/mail.log` shows delivery logs.
- `mailq` shows any pending deliveries.
- `apk add mailx && echo "Test msg from $(hostname)" | mail -s "Test msg" $YOUREMAILADDRESS` send a test message.

From outside the container:
 - Any website activity which triggers an email, such as a password reset.

A successful delivery from the webserver should look like this:
```
2023-05-24T00:40:28.770384+00:00 ropewiki_mailserver postfix/smtpd[123]: connect from ropewiki_webserver-1_default[172.19.0.5]
2023-05-24T00:40:28.779616+00:00 ropewiki_mailserver postfix/smtpd[123]: BE4F22EF281: client=ropewiki_webserver-1_default[172.19.0.5]
2023-05-24T00:40:28.827234+00:00 ropewiki_mailserver postfix/cleanup[126]: BE4F22EF281: message-id=<ropewiki.646d5cfcb9eed1.12442089@ropewiki>
2023-05-24T00:40:28.837384+00:00 ropewiki_mailserver postfix/qmgr[91]: BE4F22EF281: from=<admin@ropewiki.com>, size=1067, nrcpt=1 (queue active)
2023-05-24T00:40:28.837449+00:00 ropewiki_mailserver postfix/smtpd[123]: disconnect from ropewiki_webserver-1_default[172.19.0.5] ehlo=1 mail=1 rcpt=1 data=1 quit=1 commands=5
2023-05-24T00:40:29.679726+00:00 ropewiki_mailserver postfix/smtp[127]: BE4F22EF281: to=<admin@ropewiki.com>, relay=smtp.gmail.com[74.125.195.108]:587, delay=0.9, delays=0.06/0.03/0.25/0.56, dsn=2.0.0, status=sent (250 2.0.0 OK  1684888829 u26-20020aa7839a000000b006259e883ee9sm217323pfm.189 - gsmtp)
2023-05-24T00:40:29.680458+00:00 ropewiki_mailserver postfix/qmgr[91]: BE4F22EF281: removed
```