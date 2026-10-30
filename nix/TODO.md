# TODO

Design notes live in [`docs/`](docs/); this is the checklist.

## Decisions to make / things to find out

- [ ] **What else uses the Luca server?** The drainage badge is replaced (below). Count `/luca`
      hits in the production proxy log, check the `{{RWServerUrl}}` template and `PDFScript`, then
      replace PDF export with a new project. [docs/luca-server.md](docs/luca-server.md)
- [ ] **Cloud provider.** The repo doesn't say where the main site runs (only that the Luca server
      is on AWS, and that a "cloud backup" key pulls backups). Once known: build that provider's
      VM image (`nix build .#image` is a generic qcow2; `system.build.images` has `amazon`,
      `azure`, `google-compute`, `digital-ocean`, `linode`, ...), and confirm the provider offers
      the volume snapshots the backup design relies on.
- [ ] Who owns, and who approves sharing, a **sanitized production export** for developers and CI.

## Not yet in the NixOS module

- [ ] **Backups**: provider volume snapshots off-machine (and a vault the host can't
      delete from), restore helper and weekly restore drill, export from a clone of the snapshot,
      sanitized export, failure notifications.
- [ ] **Upgrades**: use `system.autoUpgrade.flake` on a real host (follow a `production`
      branch/tag), maintenance page, downgrade guard, `$wgReadOnlyFile`.
      [docs/upgrades.md](docs/upgrades.md)
- [ ] **Real-data upgrade tests**: fixture from the sanitized export, old to new in a VM, Playwright
      suite, log scan. [docs/real-data-upgrade-tests.md](docs/real-data-upgrade-tests.md)
- [ ] **Cutover from Docker** checklist. [docs/docker-process-review.md](docs/docker-process-review.md)
- [ ] **Site JavaScript and CSS** (published by `ropewiki-pages.service`): run the commonjs
      Playwright tests against the VM, and compare the live `MediaWiki:Common*` pages with the
      repositories before the first switch (anything edited on the live wiki and never committed is
      lost). The maintenance banner can no longer be pasted into `Common.js`; use `$wgReadOnlyFile`.
- [ ] **Real pages in the import test**: `tests/fixtures/lytle-creek.xml` is one real page with its
      templates and modules. Export what it still lacks (the 55 `Has_*` and other `Property:` pages
      it sets, `Form:Canyon`, its categories, the region pages) and add it, so SMW types and queries
      are tested too. Then check the licence of the content before the fixture is published.
- [ ] **Drainage**: build the index from the real NHDPlus download and compare it with
      production (comid 22554664 must round to 4 km²), send the two `site-pages-*.patch` changes to commonjs, and
      enable it on the real host. Alaska/Hawaii, if wanted.
- [ ] **Tile server**: try it with the real image and the production tiles (the test uses
      a stand-in), pin the image by digest instead of `latest`, add the tiles to the backups if they
      are not reproducible, and decide who sets up TLS/Cloudflare for `tiles.` on the real host.
- [ ] A job runner (`ropewiki-jobs.service`, `runJobs.php --wait`); nothing here configures one, so
      MediaWiki runs jobs inside web requests.
- [ ] A mail relay (postfix with upstream SMTP credentials). The module hardcodes `localhost:25`.
- [ ] The `www.` to apex redirect.
- [ ] The block lists (`blockips.conf`, `aws.conf`, `cloudflare.conf`), CORS `*` and the `/rwlog` 204.
- [ ] Production MariaDB tuning from `database/Dockerfile` (4G buffer pool, 512M redo log, slow
      query log) as documented defaults or an example.
- [ ] Secrets in the real host configuration (agenix/sops-nix). The module needs none for a local
      database; SMTP credentials will.
- [ ] Hardening still open: HSTS, and the version in the API's `siteinfo`.
- [ ] Try `services.nginx.virtualHosts.<host>.enableACME` against a real domain with the Let's
      Encrypt *staging* server (`security.acme.defaults.server`). Only self-signed HTTPS is
      exercised by a VM test, since a test VM can't reach a CA.

## After the MediaWiki upgrade

`services.ropewiki` runs on nixpkgs' `services.mediawiki`, but the site is on 1.39 (end of life)
and that module is written for the release nixpkgs ships (1.46). It works with `webserver = "none"`
and a few workarounds; these go away once the site moves to a current release.

- [ ] **Use `pkgs.mediawiki` as the core** and attach extensions through
      `services.mediawiki.extensions` (and `skins`) instead of copying them into our own tree. That
      drops the core tarball and its hash from `mediawiki-pins.json`, the `*.REL1_39.patch`
      files that no longer apply, and the `share/mediawiki` layout work in `packages/ropewiki.nix`.
      Extensions installed with Composer (SMW, Maps, SRF) are not in nixpkgs and stay a derivation
      of ours (`packages/composer-vendor.nix`); the others can stay pinned by `mediawiki-ext.nix`.
      nixpkgs follows one release, so the extension pins move with it. Take nixpkgs' session-cache
      patch (`keep-session-object-cache.diff`, update.php no longer logs everybody out) for free.
- [ ] **Drop the `mediawiki-init` override** in `modules/ropewiki.nix` (it replaces the module's
      script because that one runs `maintenance/run.php`, new in 1.40, and patches 1.46's
      `CliInstaller`). Then: give `services.mediawiki.passwordFile` a real value (it is
      `/dev/null` now), decide how the module's "install into an empty database" step and
      `ropewiki-install` in `vm/dev-site.nix` fit together (probably one of them goes), and
      re-check `update.php --skip-external-dependencies`, which the module passes and the override
      does not.
- [ ] **Replace `ropewiki-maintenance`** with the module's `mediawiki-maintenance` and
      `mediawiki-update`, `-edit`, `-importDump`, ... (they are installed now but broken on 1.39).
      Their configuration is `MEDIAWIKI_CONFIG` only, so first make that self-contained: today the
      repo's `LocalSettings.php` is loaded from `SiteSpecificSettings.php` and the overrides come from
      the `ROPEWIKI_OVERRIDES` environment variable, which only `ropewiki-maintenance` and the
      units set. Put the overrides in `services.mediawiki.extraConfig` and require the settings
      file from there, and `ropewiki-import` and the tests can call the new wrappers. Extension
      scripts (`rebuildData.php`) go through `mediawiki-run`.
- [ ] **Re-check what `services.mediawiki` generates** against the repo's `LocalSettings.php`
      after the move: the module sets `$wgPingback`, `$wgAuthenticationTokenVersion` and others
      that `siteSettings` pins to what the Docker site had (`$wgPingback = false`, token version
      `null` so remember-me sessions survive the cutover), and loads MonoBook and Timeless unless
      `skins` is forced empty as it is now. Read its generated file for new defaults at each nixpkgs bump.
- [ ] **Keep `webserver = "none"`**: the module hardcodes `/w/` script and `/wiki/` article paths
      (and, for nginx, its own locations), RopeWiki's URLs are at the root. Moving to the module's
      virtual host would mean redirects for every page link on the web.
- [ ] **Uploads**: the module's `uploadsDir` runs `chown -R` on every boot, which is minutes with
      70 GB, so it is `null` and `imagesDir` is ours. Revisit if the module stops doing that.
- [ ] Database rename for the cutover: the Docker site's database is `ropewiki`, `services.mediawiki`
      insists on `mediawiki` (see `docs/backups.md`). Settle whether the restore rewrites the dump or
      the production database keeps its name with `database.createLocally = false`.
