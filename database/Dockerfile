# From this working directory:
#   docker image build -f Dockerfile -t ropewiki/database .

# MySQL database; see https://hub.docker.com/_/mysql
FROM mysql:5.7-debian

# Fix for apt key errors in the ancient version of debian/mysql we're running.
RUN gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys B7B3B788A8D3785C
RUN rm /etc/apt/keyrings/mysql.gpg
RUN gpg --output /etc/apt/keyrings/mysql.gpg --export B7B3B788A8D3785C

# These values were suggested by mysqltuner.pl after the database
# had been running multiple days and was under sustained load.
RUN echo key_buffer_size=64M >> /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo innodb_buffer_pool_size=4G >> /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo innodb_log_file_size=512M >> /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo innodb_buffer_pool_instances=4 >> /etc/mysql/mysql.conf.d/mysqld.cnf

# Enable mysql slow query log
RUN echo slow_query_log=1 >> /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo slow_query_log_file=/var/log/mysql/mysql-slow.log >> /etc/mysql/mysql.conf.d/mysqld.cnf
RUN echo long_query_time=1 >> /etc/mysql/mysql.conf.d/mysqld.cnf

# Add helpful tools
RUN apt update && apt install -y vim wget curl less
RUN wget mysqltuner.pl -O /mysqltuner.pl && chmod 755 /mysqltuner.pl
