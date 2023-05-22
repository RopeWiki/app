# This image describes the RopeWiki backup manager.

# To build this image, run the following command starting from the root of the repository:
#   docker image build -f backup_manager/Dockerfile -t ropewiki/backup_manager .

FROM ubuntu:22.04

# Install necessary tools
RUN apt-get update && apt-get -y install mysql-client cron openssh-server less rsync nano

# Create a user named `backupreader` for reading database backups
RUN useradd --create-home --shell /bin/bash backupreader
USER backupreader
RUN mkdir -p /home/backupreader/backups

# Set up periodic backup
USER root
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

CMD ["/entrypoint.sh"]