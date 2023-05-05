# From this working directory:
#   docker image build -f Dockerfile -t ropewiki/database .

# MySQL database; see https://hub.docker.com/_/mysql
FROM mysql:5.7-debian

# Install necessary tools
RUN apt-get update && apt-get -y install cron openssh-server

# Create a user named `backupreader` for reading database backups
RUN useradd --create-home --shell /bin/bash backupreader
USER backupreader
RUN mkdir -p /home/backupreader/backups

# Set up periodic backup
USER root
COPY database/backup.cron /etc/cron.d/database-backup
RUN chmod 0644 /etc/cron.d/database-backup && \
    crontab /etc/cron.d/database-backup && \
    touch /var/log/cron.log

# Run our startup script after image's startup script rather than `mysqld` directly
COPY database/scripts/ /home/root/

# Provide SSH access to backupreaders
USER backupreader
COPY backup_pubkeys/authorized_keys /home/backupreader/.ssh/authorized_keys

# Start as root
USER root
RUN tail -n +2 /entrypoint.sh >> /home/root/system_start.sh && \
    mv /home/root/system_start.sh /entrypoint.sh && \
    chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["mysqld"]
