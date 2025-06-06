# This image describes the RopeWiki webserver.

# To build this image, run the following command starting from the root of the repository:
#   docker image build -f webserver/Dockerfile -t ropewiki/webserver .

FROM ubuntu:24.04

# === Install services and tools ===

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update

# Fix SSL crap related to Let's Encrypt Sept 2021 certificate expiration
RUN apt-get install -y --no-install-recommends openssl ca-certificates
RUN apt-get -y upgrade

# Install nginx
RUN apt-get install -y --no-install-recommends nginx

ARG PHP_VERSION=7.4
# Install php and associated packages
# PHP compatibility: https://www.mediawiki.org/wiki/Compatibility#PHP
# Don't start the php service after installation
# https://stackoverflow.com/a/48782486/651139
RUN apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository ppa:ondrej/php && \
    apt-get update && \
    printf '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d && \
    apt-get install -y --no-install-recommends \
        php$PHP_VERSION \
        php$PHP_VERSION-apcu \
        php$PHP_VERSION-fpm \
        php$PHP_VERSION-cli \
        php$PHP_VERSION-curl \
        php$PHP_VERSION-mysql \
        php$PHP_VERSION-imagick \
        php$PHP_VERSION-xml \
        php$PHP_VERSION-mbstring \
        php-pear

# Make version agnostic paths
RUN ln -s /etc/php/$PHP_VERSION /etc/php/current
RUN ln -s /etc/init.d/php$PHP_VERSION-fpm /etc/init.d/php-fpm

# Install the PEAR mail module and its deps.
RUN pear install --alldeps mail

# Install various tools
RUN apt-get install -y --no-install-recommends \
    curl \
    git \
    ghostscript \
    gpsbabel \
    imagemagick \
    less \
    nano \
    patch \
    sed \
    unzip \
    vim \
    wget

# Install composer
# https://stackoverflow.com/a/51446468/651139
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Bump file size upload limit
RUN sed -i 's/^;\?upload_max_filesize.*/upload_max_filesize = 10M/' /etc/php/current/fpm/php.ini
RUN sed -i 's/^;\?post_max_size.*/post_max_size = 10M/' /etc/php/current/fpm/php.ini

# Optimize php-fpm configs
RUN sed -i 's/^;\?emergency_restart_threshold.*/emergency_restart_threshold = 10/' /etc/php/current/fpm/php-fpm.conf
RUN sed -i 's/^;\?emergency_restart_interval.*/emergency_restart_interval = 1m/' /etc/php/current/fpm/php-fpm.conf
RUN sed -i 's/^;\?process_control_timeout.*/process_control_timeout = 10s/' /etc/php/current/fpm/php-fpm.conf

# php-fpm pool settings
COPY ./webserver/fpm-pool.conf /etc/php/current/fpm/pool.d/www.conf


# === Install MediaWiki ===
ARG MW_VERSION="1.35.14"
ARG MW_REL_BRANCH="REL1_35"
RUN wget https://releases.wikimedia.org/mediawiki/${MW_VERSION%.*}/mediawiki-$MW_VERSION.tar.gz && \
    tar xvzf mediawiki-$MW_VERSION.tar.gz && \
	mv mediawiki-$MW_VERSION /usr/share/nginx/html/ropewiki && \
	rm mediawiki-$MW_VERSION.tar.gz

# Configure quick symlink
RUN ln -s /usr/share/nginx/html/ropewiki /rw

# === Install extensions ===

WORKDIR /rw
RUN composer require --no-update mediawiki/semantic-media-wiki 3.2.3
RUN composer require --no-update mediawiki/header-footer 3.0.1
RUN composer require --no-update mediawiki/maps 8.0.0
RUN composer require --no-update mediawiki/semantic-result-formats 3.2
RUN COMPOSER_ALLOW_SUPERUSER=yes composer install
WORKDIR /

# After MW 1.35 the "jquery.ui.xyz" modules have been removed and you just call "jquery.ui".
# This is fixed in later version of SemanticResultFormats (after 3.2).
RUN cd /rw/extensions/SemanticResultFormats/formats/slideshow && \
  sed -i 's/jquery.ui.slider/jquery.ui/' SRF_SlideShow.php resources/ext.srf.slideshow.js

# Copy missing 'powered by semantic mediawiki' image (seems peculiar to SMW 2.1 version)
COPY ./webserver/html/ropewiki/extensions/SemanticMediaWiki/smw_button.png /rw/extensions/usr/share/nginx/html/ropewiki/vendor/mediawiki/semantic-media-wiki/res/images/smw_button.png

# Note: We do not need to follow the rest of the instructions to install
# SemanticMediaWiki 2.1 because the files we will copy over are already
# configured.  But for reference:
# https://web.archive.org/web/20150314234734/http://semantic-mediawiki.org/wiki/Help:Installation

# These all track $MW_REL_BRANCH
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-CheckUser CheckUser && cd CheckUser && git checkout $MW_REL_BRANCH
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-MagicNoCache MagicNoCache && cd MagicNoCache && git checkout $MW_REL_BRANCH
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-MyVariables MyVariables && cd MyVariables && git checkout $MW_REL_BRANCH
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-PageForms PageForms && cd PageForms && git checkout $MW_REL_BRANCH
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-SphinxSearch SphinxSearch && cd SphinxSearch && git checkout $MW_REL_BRANCH
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-UrlGetParameters UrlGetParameters && cd UrlGetParameters && git checkout $MW_REL_BRANCH
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-UserMerge UserMerge && cd UserMerge && git checkout $MW_REL_BRANCH

# Used everywhere! Note: arrays & variables will break one day: https://phabricator.wikimedia.org/T250963
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-Arrays Arrays && cd Arrays && git checkout $MW_REL_BRANCH
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-Variables Variables && cd Variables && git checkout $MW_REL_BRANCH

# These just use master branch
RUN cd /rw/extensions && git clone https://gitlab.com/HydraWiki/extensions/embedvideo.git EmbedVideo
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-SemanticRating SemanticRating

# Present in main site but not here:
# APC
# HeaderTabs
# SimpleAntiSpam
# UserAdmin
# xml2wiki-dr

# === Install SphinxSearch ===
RUN apt-get install -y --no-install-recommends sphinxsearch

# Install Sphinx PHP API
RUN cd /rw/extensions/SphinxSearch && composer install
 
# required for logging
RUN mkdir -p /var/data/sphinx

# === Customize site (including custom extensions) ===

# MediaWiki: Copy in our customizations
COPY ./webserver/html /usr/share/nginx/html

# nginx: Copy in our customizations
COPY ./webserver/nginx /etc/nginx
RUN rm /etc/nginx/sites-enabled/default

# Sphinx: Move our config file into place
RUN cd /rw/extensions/SphinxSearch && mv -f sphinx.conf /etc/sphinxsearch/sphinx.conf

# Apply our custom patch to the SphinxSearch code
# (allows substring search on page titles instead of exact match from the start)
RUN cd /rw/extensions/SphinxSearch && patch -l < SphinxMWSearch.$MW_REL_BRANCH.patch

# Apply Arrays patch to suppress warning notice.
RUN cd /rw/extensions/Arrays && patch -l < ExtArrays.php.$MW_REL_BRANCH.patch

# Sphinx: Setup cron job
RUN apt-get install -y cron \
 && mv -f /rw/extensions/SphinxSearch/sphinx.cron /etc/cron.d/sphinxsearch-update \
 && chmod 0644 /etc/cron.d/sphinxsearch-update \
 && crontab /etc/cron.d/sphinxsearch-update \
 && touch /var/log/cron.log

# robots: Copy the robots.txt candidates that can be selected at startup
COPY ./webserver/robots /rw/robots

# === Set up startup behavior ===
USER root
COPY ./webserver/scripts/system_start.sh /root/system_start.sh

# Set default parameters (that may be overwritten via environment variables)
ENV WG_DB_SERVER=ropewiki_db
ENV WG_DB_USER=ropewiki
ENV WG_DB_PASSWORD=ropewikidatabasepassword
ENV WG_HOSTNAME=localhost
ENV WG_PROTOCOL=http
ENV WG_SECRET_KEY=04f44118ad1899762bc60ed90d778aa72f92e9dc0d298c8f327755e503ceb84a
ENV WG_UPGRADE_KEY=1ce9e4e2a0a3bf63
ENV RW_ROBOTS=robots_dev.txt

ARG codebaseversion=When this image was built with Docker, <pre>codebaseversion</pre> Docker arg was not specified.
RUN echo "<html><body>${codebaseversion}</body></html>" > /rw/codebase_version.html

HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD curl -f http://localhost/ || exit 1

CMD sh /root/system_start.sh

# To explore the system to see how things have been set up, following building:
#   docker container run -it ropewiki/webserver
