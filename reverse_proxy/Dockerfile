FROM nginx

RUN apt-get update
RUN apt-get -y install certbot python3-certbot-nginx goaccess procps vim less wget curl

# Set up startup behavior
COPY ./reverse_proxy/scripts/system_start.sh /root/system_start.sh
CMD sh /root/system_start.sh

# Configure nginx
COPY ./reverse_proxy/nginx.conf /etc/nginx/nginx.conf
COPY ./reverse_proxy/services.conf /etc/nginx/services.conf
COPY ./reverse_proxy/blockips.conf /etc/nginx/blockips.conf
COPY ./reverse_proxy/aws.conf /etc/nginx/aws.conf
COPY ./reverse_proxy/cloudflare.conf /etc/nginx/cloudflare.conf