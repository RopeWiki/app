# From this working directory:
#   docker image build -f Dockerfile -t ropewiki/reverse_proxy .

FROM nginx

RUN apt-get update
RUN apt-get -y install certbot python-certbot-nginx
COPY nginx.conf /etc/nginx/nginx.conf
COPY services.conf /etc/nginx/services.conf
COPY blockips.conf /etc/nginx/blockips.conf
