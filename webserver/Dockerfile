# This image represents the current production deployment of the RopeWiki
# server.

# To build this image, run this in this folder:
#   docker image build -f Dockerfile -t ropewiki/webserver .

# !Important -- if you have moved the 'images' assets folder into the 'html/ropewiki' 
# subfolder already, move them out before doing the docker image build, because the 
# build daemon sends the entire contents of the folder where the dockerfile is located,
# and images is 17GB. Similarly if you have a .sql backup file in 'mysql/backup'.

FROM ubuntu:14.04

# === Install services and tools ===

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update

# Install nginx
RUN apt-get install -y --no-install-recommends nginx

# Install php
# Don't start the php service after installation
# https://stackoverflow.com/a/48782486/651139
RUN printf '#!/bin/sh\nexit 0' > /usr/sbin/policy-rc.d && \
    apt-get install -y --no-install-recommends php5-fpm php5-cli php5-mysql

# Install various tools
RUN apt-get install -y --no-install-recommends wget unzip git nano sed curl imagemagick php5-imagick

# Install composer
COPY ./scripts/install_composer.sh /root/install_composer.sh
RUN sh /root/install_composer.sh && \
    mv composer.phar /usr/local/bin/composer

# === Install MediaWiki ===

# Retrieve MediaWiki installation package and follow installation instructions:
# https://phabricator.wikimedia.org/source/mediawiki/browse/REL1_25/INSTALL
RUN wget https://releases.wikimedia.org/mediawiki/1.24/mediawiki-1.24.1.tar.gz && \
    tar xvzf mediawiki-1.24.1.tar.gz && \
	mv mediawiki-1.24.1 /usr/share/nginx/html/ropewiki && \
	rm mediawiki-1.24.1.tar.gz

# Configure quick symlink
RUN ln -s /usr/share/nginx/html/ropewiki /rw

# === Install extensions ===

COPY ./html/ropewiki/composer.json /usr/share/nginx/html/ropewiki/composer.json
RUN cd /rw && composer install

# Note: We do not need to follow the rest of the instructions to install
# SemanticMediaWiki 2.1 because the files we will copy over are already
# configured.  But for reference:
# https://web.archive.org/web/20150314234734/http://semantic-mediawiki.org/wiki/Help:Installation

# Note: we can't use gerrit.wikimedia.org because they apparently use a cipher
# that isn't supported in Ubuntu 14, and there don't appear to be any gnutls
# backports to fix that.  See:
# https://github.com/NVIDIA/nvidia-docker/issues/714#issuecomment-386244620

RUN cd /rw/extensions && git clone https://github.com/SemanticMediaWiki/SemanticCompoundQueries.git && cd SemanticCompoundQueries && git checkout f5eed72
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-SemanticDrilldown SemanticDrilldown && cd SemanticDrilldown && git checkout a569de7
RUN cd /rw/extensions && git clone https://github.com/RopeWiki/SemanticFormsInputs.git && cd SemanticFormsInputs && git checkout e8254cf
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-SemanticRating SemanticRating && cd SemanticRating && git checkout 3af01d6
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-CategoryTree CategoryTree && cd CategoryTree && git checkout 52c3eb7
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-CheckUser CheckUser && cd CheckUser && git checkout 99f4a22
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-ContributionScores ContributionScores && cd ContributionScores && git checkout 7e02f8a
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-UserMerge UserMerge && cd UserMerge && git checkout 22c450d
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-Arrays Arrays && cd Arrays && git checkout f28592b
RUN cd /rw/extensions && git clone https://gitlab.com/HydraWiki/extensions/embedvideo.git EmbedVideo && cd EmbedVideo && git checkout bdc2cf1
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-MagicNoCache MagicNoCache && cd MagicNoCache && git checkout a6aac2c
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-MyVariables MyVariables && cd MyVariables && git checkout 70cf94b
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-Scribunto Scribunto && cd Scribunto && git checkout 10abeb5
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-UrlGetParameters UrlGetParameters && cd UrlGetParameters && git checkout 68afd03
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-Variables Variables && cd Variables && git checkout 6f4bbd0
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-PdfHandler PdfHandler && cd PdfHandler && git checkout 5e29202
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-googleAnalytics googleAnalytics && cd googleAnalytics && git checkout ce5ef02
RUN cd /rw/extensions && git clone https://gitlab.com/troyengel/Preloader && cd Preloader && git checkout 4b06d0e3
RUN cd /rw/extensions && git clone https://github.com/RopeWiki/SemanticForms && cd SemanticForms && git checkout 9169c63
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-skins-Vector Vector && cd Vector && git checkout fad72e2
RUN cd /rw/extensions && git clone https://github.com/wikimedia/mediawiki-extensions-MultimediaViewer.git MultimediaViewer && cd MultimediaViewer && git checkout REL1_24

# Present in main site but not here:
# APC
# HeaderTabs
# SimpleAntiSpam
# UserAdmin
# xml2wiki-dr


# === Install SphinxSearch ===

RUN apt-get install -y --no-install-recommends sphinxsearch

# download Mediawiki v1.24 compatible extension
RUN cd rw/extensions \
 && curl -O https://gerrit.wikimedia.org/r/plugins/gitiles/mediawiki/extensions/SphinxSearch/+archive/refs/heads/REL1_24.tar.gz \
 && mkdir -p SphinxSearch \
 && tar -xzf REL1_24.tar.gz -C SphinxSearch \
 && rm REL1_24.tar.gz

# need to manually download sphinxapi.php if not using composer to install (composer installs the latest version, which we don't want)
RUN cd rw/extensions/SphinxSearch \
 && curl -O https://raw.githubusercontent.com/romainneutron/Sphinx-Search-API-PHP-Client/master/sphinxapi.php

# copy our ropewiki specific configuration file over
COPY ./html/ropewiki/extensions/SphinxSearch/sphinx.conf /etc/sphinxsearch/sphinx.conf

# replace mediawiki extension with our modified version (allows substring search on page titles instead of exact match from the start)
COPY ./html/ropewiki/extensions/SphinxSearch/SphinxMWSearch.php /rw/extensions/SphinxSearch/SphinxMWSearch.php

# required for logging
RUN mkdir -p /var/data/sphinx

# setup chron job
COPY ./html/ropewiki/extensions/SphinxSearch/sphinx.cron /etc/cron.d/sphinxsearch-update
RUN chmod 0644 /etc/cron.d/sphinxsearch-update
RUN crontab /etc/cron.d/sphinxsearch-update
RUN touch /var/log/cron.log


# === Customize site (including custom extensions) ===

# Copy in our MediaWiki customizations
COPY ./html /usr/share/nginx/html

# Copy in our nginx customizations
COPY ./nginx /etc/nginx
RUN rm /etc/nginx/sites-enabled/default

# Copy in our MMV customizations (do multiple browser back on close instead of navigate forward to original page)
COPY ./html/ropewiki/extensions/MultimediaViewer/mmv.js /rw/extensions/MultimediaViewer/resources/mmv 

# === Set up startup behavior ===

COPY ./scripts/system_start.sh ./root/system_start.sh

# Set default parameters (that may be overwritten via environment variables)
ENV WG_DB_SERVER ropewiki_db
ENV WG_DB_USER ropewiki
ENV WG_DB_PASSWORD ropewikidatabasepassword
ENV WG_HOSTNAME localhost
ENV WG_PROTOCOL http
ENV WG_SECRET_KEY 04f44118ad1899762bc60ed90d778aa72f92e9dc0d298c8f327755e503ceb84a
ENV WG_UPGRADE_KEY 1ce9e4e2a0a3bf63

CMD sh /root/system_start.sh

# To explore the system to see how things have been set up, following building:
#   docker container run -it ropewiki/legacy_webserver

# /etc/php5/fpm/php-fmp.conf