# docker build -t postfix_test .
# docker run -it -v c:\ropewiki\postfix\mount:/external postfix_test /bin/bash
# docker run -it -v `pwd`:/external postfix_test /bin/bash

FROM ubuntu:14.04

# https://blog.codinghorror.com/so-youd-like-to-send-some-email-through-code/
ARG DEBIAN_FRONTEND=noninteractive
# All options: https://gist.github.com/gene1wood/e4dd448513cb425b5ec398f95cda2462
RUN echo "postfix postfix/mailname string ropewiki.com" | debconf-set-selections
RUN echo "postfix postfix/main_mailer_type string 'Internet Site'" | debconf-set-selections
RUN echo "postfix postfix/protocols select all" | debconf-set-selections
RUN apt-get update && apt-get install --assume-yes postfix mailutils

COPY ./system_start.sh /system_start.sh

CMD bash /system_start.sh

# echo "Test message from local Docker container" | mail -s "Local mail test" bjpcaltech@gmail.com
# echo "Test message from monolith" | mail -s "Monolith mail test" bjpcaltech@gmail.com
