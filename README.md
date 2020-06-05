## Ropewiki Frontend Application

### Dockerfile
The configuration intended to bring up a copy of the RopeWiki website, and eventually used for the primary site.

### Dockerfile_legacy
Dockerfile_legacy is used to build a legacy system intended to be as similar to the currently-deployed RopeWiki site as practical to facilitate practicing restoring the database and practicing upgrades and migrations.  When complete, this image should be as similar to the server accessible at ropewiki.com as practical.  Remaining items include configuring MediaWiki, installing existing extensions, and copying in custom extensions (they don't exist anywhere else).

Once the image created by Dockerfile_legacy is ready, an attached MySQL container can be brought up with docker-compose_legacy.yaml to test operation of the entire system.
