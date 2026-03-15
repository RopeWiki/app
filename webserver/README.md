# webserver

This folder contains the resources necessary to build the RopeWiki webserver Docker image.


## Upload limits
There are 4 places which effect the upload limit, in order they are:
 - reverse_proxy (nginx)
 - webserver (nginx)
 - php config
 - mediawiki config

### nginx
Nginx will return a HTTP 413 error if `client_max_body_size` is exceed by an uploaded file.

This is a "hard" error, and will likely give the user an ugly error page. Therefore it's
important that this value is equal to or higher than the php/mediawiki value.

Both the webserver & reverse_proxy need this value set. It's set at the global (http {...})
level to avoid confusion around different paths getting different limits.

### Mediawiki
Mediawiki will pick whichever of these three is the lowest, and give a "soft" error before
the upload begins:
 - `upload_max_filesize` (php.ini)
 - `post_max_size` (php.ini)
 - `wgMaxUploadSize`, defaults to 100MB (LocalSettings.php)
