# Real-data upgrade tests

Part of the Nix migration; see [TODO](../TODO.md) for the checklist. Builds on [backups](backups.md) (the fixture) and [upgrades](upgrades.md) (the flow under test).

**Goal:** before a change reaches production, run the *whole upgrade* against a copy of real data in
a NixOS VM test, drive the site like a visitor and an editor, and fail on any error the services
log. This is what the empty-schema tests cannot do: they say the plumbing works, not that the
site's templates, forms, semantic queries and uploads still work after the upgrade.

## Fixture: turn production backups into something a test can import

Built from the backup pipeline above, not by hand:
- **Source:** the daily SQL export (sanitized, [Backups step 6](backups.md#ideal-implementation)) plus the
  uploads from the same snapshot, plus a copy of the SMW setup state.
- **Two sizes.** *Small:* a few hundred pages chosen by category (some canyons with all their
  templates, forms, properties, `MediaWiki:` pages, `Module:` pages), only the images those pages
  reference, rebuilt with SMW's `rebuildData.php` so the semantic data is consistent. Fast enough
  for every CI run. *Full:* the whole sanitized export and image set for the pre-production
  rehearsal (hours, on a build machine).
- **Format and delivery.** Not committed (1.2+ GB and 18+ GB). Published to object storage with a
  manifest (hash, MariaDB version, MediaWiki/SMW version it was taken from). The test consumes a
  directory given by an environment variable (`ROPEWIKI_FIXTURE=/path`), passed into the VM with
  `virtualisation.sharedDirectories` (virtiofs) so nothing is copied into the Nix store. CI fetches
  it with credentials; locally you point at an unpacked copy. Loading is either "import the SQL with
  `--one-database ropewiki`" (simple, slower) or a prebuilt MariaDB datadir image (fast, but pinned to
  one MariaDB major version); start with the first.

## The test: old system, load data, upgrade, verify

1. Boot the VM on the **currently deployed** revision (a previous flake ref, as a
   `specialisation` or a second system closure).
2. Import the fixture (database, uploads), start the site, run the verification suite once as a
   **baseline** on the old code.
3. Switch to the **new** revision with `switch-to-configuration` (the real upgrade path, including
   `ropewiki-init`/`update.php`, the maintenance page, the downgrade guard).
4. Run the same suite again and compare. Pages that rendered before must still render, with the same
   text where it should not have changed.

## Verification suite (browser automation)

- **Playwright** in the test (nixpkgs has `playwright-driver.browsers` and the Python bindings, so
  browsers come from the store, not a download). Run it from a second VM node, so the browser is
  not inside the machine under test, against `https://machine` (self-signed, so
  `ignore_https_errors=True`).
- Coverage worth having first: anonymous reading of representative pages from each namespace
  (canyon, condition, incident, event, vote, list), the map pages (Leaflet loads, no JS exception,
  no failed network requests), a PageForms form opens and saves a test edit, an SMW `#ask` table and
  a result-format chart render, Sphinx-backed search returns a known page, login with a test
  account (created by `createAndPromote.php`), an upload with a thumbnail (ImageMagick) and a PDF
  upload (ghostscript), `kml_to_gpx.php` on a fixture KML, `robots.txt`, `Special:Version` and
  `composer.json` hidden, and, only if the Luca server still exists by then, the `/luca/` path.
- Record for every page: HTTP status, JS console errors, failed requests, screenshots (kept as
  test artefacts so a human can eyeball the old/new diff).

## Log scanning (the test also fails on quiet errors)

After the suite, collect and scan: `journalctl` for `ropewiki-init`, `phpfpm-ropewiki`, `nginx`,
`mysql`/`mariadb`, `ropewiki-searchd`, and the files under `/var/log/nginx`, `/var/log/ropewiki-sphinx`
and the MariaDB error log. Fail on PHP `Fatal`/`Warning`/`Deprecated`/`Notice`, exceptions, MariaDB
errors and warnings (deadlocks, "table is marked as crashed"), nginx `[error]`/`[emerg]`, searchd
`FATAL`/`WARNING`. A checked-in **allowlist** of known benign messages (with a reason each) keeps
the test honest instead of ignoring whole categories. Run this in development mode too, because
production mode deliberately hides the warnings.

## Interactive use

`nix run .#checks.x86_64-linux.upgrade.driverInteractive` starts the test driver as a Python shell
instead of running the script: `start_all()`, `machine.wait_for_unit(...)`, import the fixture by
hand, `machine.shell_interact()`, or open the site in a real browser (forward a port with
`QEMU_NET_OPTS="hostfwd=tcp::8443-:443"`, to be verified for the test driver in this nixpkgs). The
same script then runs unattended in CI. Developers can poke at a real copy of the site, with the new code
running, without touching production.

Open questions: size of the "small" fixture that still catches real regressions (start with ~20
canyons and widen when something slips through); how often the fixture is refreshed; whether CI
has enough disk and RAM for the full one (MariaDB wants a few GB of memory; the full test is
better on a dedicated runner); who approves sharing even a sanitized dump.
