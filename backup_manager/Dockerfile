# This image describes the RopeWiki backup manager.

# To build this image, run the following command starting from the root of the repository:
#   docker image build -f backup_manager/Dockerfile -t ropewiki/backup_manager .

FROM mysql:5.7-debian

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

# Create a user named `backupreader` for reading database backups
RUN useradd --create-home --shell /bin/bash backupreader
RUN mkdir -p /home/backupreader/backups && chown backupreader /home/backupreader/backups
VOLUME /home/backupreader/backups

# Set up periodic backup
COPY backup_manager/backup.cron /etc/cron.d/database-backup
RUN chmod 0644 /etc/cron.d/database-backup && \
    crontab /etc/cron.d/database-backup && \
    touch /var/log/cron.log

# Run our startup script on image's startup
COPY backup_manager/scripts/ /

# Provide SSH access to backupreaders
USER backupreader
COPY backup_manager/pubkeys/authorized_keys /home/backupreader/.ssh/authorized_keys

# Start as root
USER root

ENTRYPOINT ["/bin/bash"]
CMD ["/entrypoint.sh"]
