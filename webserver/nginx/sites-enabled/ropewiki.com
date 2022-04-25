# The content of this file is included within an http block by nginx.conf

server {
	listen 80 default_server;
	listen [::]:80 default_server ipv6only=on;
        #add_header Access-Control-Allow-Origin www.ropewiki.com;
        client_max_body_size 5M;
	root /usr/share/nginx/html/ropewiki;
	index index.php index.html index.htm;

	# Make site accessible from http://localhost/
	server_name localhost;

    location / {
        try_files $uri $uri/ @rewrite;
    }

    location @rewrite {
        rewrite ^/(.*)$ /index.php?title=$1&$args;
    }

	error_page 404 /404.html;

	# redirect server error pages to the static page /50x.html
	#
	error_page 500 502 503 504 /50x.html;
	location = /50x.html {
		root /usr/share/nginx/html/ropewiki;
	}

	# pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
	#
	location ~ \.php$ {
		fastcgi_split_path_info ^(.+\.php)(/.+)$;
	#	# NOTE: You should have "cgi.fix_pathinfo = 0;" in php.ini
	#
	#	# With php5-cgi alone:
	#	fastcgi_pass 127.0.0.1:9000;
	#	# With php5-fpm:
		fastcgi_pass unix:/var/run/php/php7.4-fpm.sock;
		fastcgi_index index.php;
		include fastcgi_params;
	}

	# deny access to .htaccess files, if Apache's document root
	# concurs with nginx's one
	#
	#location ~ /\.ht {
	#	deny all;
	#}

    location ~* \.(jpg|jpeg|gif|png|css|js|ico|xml)$ {
        access_log        off;
        log_not_found     off;
        expires           360d;
    }
}
