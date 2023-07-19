FROM nginx

RUN apt-get update
RUN apt-get -y install certbot python3-certbot-nginx procps less cron

# Set up startup behavior
COPY ./reverse_proxy/scripts/system_start.sh /root/system_start.sh
CMD sh /root/system_start.sh

# Configure nginx
COPY ./reverse_proxy/nginx.conf /etc/nginx/nginx.conf
COPY ./reverse_proxy/services.conf /etc/nginx/services.conf
COPY ./reverse_proxy/blockips.conf /etc/nginx/blockips.conf
