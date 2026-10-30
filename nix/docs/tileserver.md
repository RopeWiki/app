# Tile server

Upstream PR [RopeWiki/app#155](https://github.com/RopeWiki/app/pull/155) ("Setup tileserver for
public land tiles") added a map tile server on its own domain, `tiles.ropewiki.com`, for the
public-lands-at-risk tiles. It is a container, not part of the wiki: nothing in MediaWiki's
configuration refers to it, pages use the URL.

## What the PR did

| Docker | Here |
|---|---|
| compose service `ropewiki_tileserver`, image `maptiler/tileserver-gl:latest` | `virtualisation.oci-containers.containers.ropewiki-tileserver` (podman), `services.ropewiki.tileserver.image` |
| `/mnt/rwimages/tiles:/data` (the images volume's `tiles` directory) | `dataDir`, default `<imagesDir>/tiles`, mounted read-only |
| `command: -c config.json`, `user: root` | `configFile`, `user = "root"` |
| `ports: 8080:8080` (all interfaces) | `127.0.0.1:<port>:8080`; only nginx reaches it |
| reverse proxy `server { server_name tiles.<host>; proxy_pass http://ropewiki_tileserver:8080; }` | `services.nginx.virtualHosts."tiles.<hostName>"`, `hostName` is configurable |
| Cloudflare in front for caching | not our business; TLS for the virtual host is set on `services.nginx.virtualHosts` like the site's |
| `PHP_VERSION=8.2` in the Dockerfile (same PR) | not relevant: `services.ropewiki.phpPackage` |

## Why a container and not a systemd service

nixpkgs has no `tileserver-gl`. It is a Node program with native renderers (MapLibre GL Native,
`canvas`) that npm builds against system libraries; packaging that is a project of its own, and
the container is what runs in production. The unit is called `podman-ropewiki-tileserver.service`
(`ropewiki-logs tileserver`). If a native package appears, `modules/tileserver.nix` is the only
file that changes.

## Data

The tiles (`.mbtiles`/`.pbf` files and `config.json`) are not in the repository. Copy them to
`dataDir`; the module creates the empty directory so the container can start. tileserver-gl reads
`config.json` at start, so restart the unit after changing it.

## Test

`checks.<system>.tileserver` replaces the image with a stub (a static file server that records its
arguments), because a test cannot pull from a registry. It shows the mount, the arguments, the
loopback-only port and the virtual host; it does not test tileserver-gl.
