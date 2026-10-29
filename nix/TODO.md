# TODO

Design notes live in [`docs/`](docs/); this is the checklist.

## Decisions to make / things to find out

- [ ] **What really uses the Luca server?** Count `/luca` hits in the production proxy log, check
      the `{{RWServerUrl}}` template and `PDFScript`. Then replace PDF export and the waterflow
      lookup with new projects. [docs/luca-server.md](docs/luca-server.md)
- [ ] **Cloud provider.** The repo doesn't say where the main site runs (only that the Luca server
      is on AWS, and that a "cloud backup" key pulls backups). Once known: build that provider's
      VM image (`nix build .#image` is a generic qcow2; `system.build.images` has `amazon`,
      `azure`, `google-compute`, `digital-ocean`, `linode`, ...), and confirm the provider offers
      the volume snapshots the backup design relies on.
- [ ] Who owns, and who approves sharing, a **sanitized production export** for developers and CI.

## Not yet in the NixOS module

- [x] **Backups, first part** (`services.ropewiki.backup`, opt-in): hourly btrfs snapshots (24 h),
      daily SQL export + first-of-day snapshots (30 days), freshness monitor.
      [docs/backups.md](docs/backups.md)
- [ ] **Backups, the rest**: provider volume snapshots off-machine (and a vault the host can't
      delete from), restore helper and weekly restore drill, export from a clone of the snapshot,
      sanitized export, failure notifications.
- [x] **Upgrade gate**: `system.preSwitchChecks` requires a backup less than an hour old, and an
      automatic upgrade starts a backup first.
- [ ] **Upgrades, the rest**: use `system.autoUpgrade.flake` on a real host (follow a `production`
      branch/tag), maintenance page, downgrade guard, `$wgReadOnlyFile`.
      [docs/upgrades.md](docs/upgrades.md)
- [ ] **Real-data upgrade tests**: fixture from the sanitized export, old to new in a VM, Playwright
      suite, log scan. [docs/real-data-upgrade-tests.md](docs/real-data-upgrade-tests.md)
- [ ] **Cutover from Docker** checklist. [docs/docker-process-review.md](docs/docker-process-review.md)
- [x] **Site JavaScript and CSS** from the `commonjs`/`commoncss` flake inputs, published by
      `ropewiki-pages.service`. Still to do: run the commonjs Playwright tests against the VM, and
      compare the live `MediaWiki:Common*` pages with the repositories before the first switch
      (anything edited on the live wiki and never committed is lost). The maintenance banner can no
      longer be pasted into `Common.js`; use `$wgReadOnlyFile` (see above).
- [ ] A job runner (`ropewiki-jobs.service`, `runJobs.php --wait`); nothing here configures one, so
      MediaWiki runs jobs inside web requests.
- [ ] A mail relay (postfix with upstream SMTP credentials). The module hardcodes `localhost:25`.
- [ ] The `www.` to apex redirect.
- [ ] The block lists (`blockips.conf`, `aws.conf`, `cloudflare.conf`), CORS `*` and the `/rwlog` 204.
- [ ] Production MariaDB tuning from `database/Dockerfile` (4G buffer pool, 512M redo log, slow
      query log) as documented defaults or an example.
- [ ] Secrets in the real host configuration (agenix/sops-nix). The module needs none for a local
      database; SMTP credentials will.
- [ ] Hardening still open: HSTS, `codebase_version.html` (shows the git commit and log to
      everyone), and the version in the API's `siteinfo`.
- [ ] Try `services.nginx.virtualHosts.<host>.enableACME` against a real domain with the Let's
      Encrypt *staging* server (`security.acme.defaults.server`). Only self-signed HTTPS is
      exercised by a VM test, since a test VM can't reach a CA.
