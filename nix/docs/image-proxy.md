# Image proxy mode

A development site has none of the live site's roughly 70 GB of uploads (photos, KML, PDFs).
`services.ropewiki.imageProxy` shows the other site's files instead of copying them. This is the
mode described in [Image Proxy Mode](https://github.com/RopeWiki/app/wiki/Image-Proxy-Mode) on the
repository wiki, which names a `DEV_IMAGE_PROXY_MODE` variable for the Docker setup; that variable
is not in this repository, so only the Nix module implements it.

```nix
services.ropewiki.imageProxy = "https://ropewiki.com";
```

Two things happen, as on the wiki page:

- **MediaWiki's own links.** `$wgUploadPath` is `<url>/images`, `$wgThumbPath` is
  `<url>/images/thumb` and `$wgGenerateThumbnailOnParse` is false, so every file and thumbnail
  MediaWiki knows about is linked to the other site and nothing is rendered here. The browser
  fetches these itself.
- **nginx for the rest.** Requests for `/images/...` that page text hard-codes (not through
  MediaWiki) are fetched by nginx from `<url>/images/`, with the other site's `Host` and TLS name.
  Additions to the wiki page's snippet: the certificate is verified against the system CAs, only
  `GET` and `HEAD` are allowed, and the visitor's cookies are not passed on.

## Caveats

- Read-only. An upload still works but the file is not shown, because every link points at the
  other site.
- **ropewiki.com may not answer nginx.** Cloudflare puts a browser check in front of the whole
  site, `/images/` included (a plain `curl` of an image gets `403`, `cf-mitigated: challenge`, on
  2026-10-29). The first mechanism is unaffected, since browsers pass the check; the second may
  return that 403 to nginx. The first covers every file MediaWiki knows about. Hard-coded paths
  need an origin the server can reach, or an exemption for this host's address on the live site.
  This was not tried against the live site.
- Without a resolver, nginx looks the host name up when it starts and does not start without DNS.
  Set `services.nginx.resolver.addresses` and it looks the name up when a file is requested
  instead: nginx starts with no network, and files fail with 502 until DNS answers.
- `mode = "production"` plus `imageProxy` prints a warning: it makes sense only for development.

## In `nix run .#vm`

Off, until it has been validated against a real database. It was on once and the Lytle Creek page
showed no proxied images. The likely reason: MediaWiki only links a file when its database has a
row for it (the `image` table and the `File:` page). Pages imported from Special:Export carry the
wikitext but not those rows, so there are no URLs to rewrite; only a database export, or importing
the `File:` pages with their file records, can supply them. The ones written into page text as
`/images/...` do go through nginx, but ropewiki.com's Cloudflare may refuse that (see above).

To try it anyway, add this to the VM configuration (`nix/vm/configuration.nix` has the same as a
comment); `10.0.2.3` is QEMU's built-in DNS forwarder, which lets nginx start with no network:

```nix
services.ropewiki.imageProxy = "https://ropewiki.com";
services.nginx.resolver = { addresses = [ "10.0.2.3" ]; ipv6 = false; };
```

## Tests

`nix build .#checks.x86_64-linux.image-proxy` starts a second VM as the "other site", with two
virtual hosts and different certificates, so a request without the right TLS name or `Host` fails
(removing `proxy_ssl_server_name` makes the test fail). It checks the URLs MediaWiki produces for a
file and its thumbnail, that hard-coded paths are fetched, that the other site sees its own host
name and no cookies, that 404 passes through, and that `POST` and `PUT` are refused. It then switches the machine to a
configuration with a resolver (a small DNS server on the other VM; the hosts-file entry is removed)
and checks that nginx restarts while the name cannot be resolved, answers 502, and recovers when DNS
returns. Forcing the old behaviour makes that step fail.
