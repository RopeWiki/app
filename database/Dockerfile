# From this working directory:
#   docker image build -f Dockerfile -t ropewiki/database .

# MySQL database; see https://hub.docker.com/_/mysql
FROM mysql:5.7-debian

# These values were suggested by mysqltuner.pl after the database
# had been running multiple days and was under sustained load.
RUN echo key_buffer_size=64M >> /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo innodb_buffer_pool_size=4G >> /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo innodb_log_file_size=512M >> /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo innodb_buffer_pool_instances=4 >> /etc/mysql/mysql.conf.d/mysqld.cnf

# Add helpful tools
RUN apt update && apt install -y vim wget curl less
RUN wget mysqltuner.pl -O /mysqltuner.pl && chmod 755 /mysqltuner.pl