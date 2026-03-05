# This image describes the RopeWiki backup manager.

# To build this image, run the following command starting from the root of the repository:
#   docker image build -f backup_manager/Dockerfile -t ropewiki/backup_manager .

FROM mysql:5.7-debian

# The mysql:5.7-debian is built upon Debian Buster, which is EOL. Until Mediawiki is upgraded to a version which has confirmed support for later Mysql (probably 8) we have to keep the container alive.
RUN sed -i '/^deb http:\/\/deb.debian.org/d; s/^# deb http:\/\/snapshot/deb http:\/\/snapshot/' /etc/apt/sources.list
RUN echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99no-check-valid-until

# Fix for apt key errors in the ancient version of debian/mysql we're running.
RUN gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys B7B3B788A8D3785C
RUN rm /etc/apt/keyrings/mysql.gpg
RUN gpg --output /etc/apt/keyrings/mysql.gpg --export B7B3B788A8D3785C

# Install necessary tools
RUN apt-get update && apt-get -y install \
    cron \
    less \
    nano \
    openssh-server \
    rsync \
    zstd

# Create the `backupreader` user, with direct SSH access.
RUN useradd --create-home --shell /bin/bash backupreader
USER backupreader
RUN mkdir -p /home/backupreader/backups
COPY backup_manager/pubkeys/authorized_keys /home/backupreader/.ssh/authorized_keys

# Install the crontab. Note this runs as `backupreader` user.
USER root
COPY --chmod=0644 backup_manager/backup.cron /etc/cron.d/database-backup

# Install the backup and entry scripts.
COPY backup_manager/scripts/ /

# Start as root
USER root

ENTRYPOINT ["/bin/bash"]
CMD ["/entrypoint.sh"]
