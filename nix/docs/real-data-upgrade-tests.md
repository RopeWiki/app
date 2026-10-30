# Real-data upgrade tests (not built)

See [TODO](../TODO.md). Builds on [backups](backups.md) (the fixture) and [upgrades](upgrades.md)
(the flow under test).

**Goal:** before a change reaches production, run the whole upgrade against a copy of real data in a
NixOS VM test, drive the site like a visitor and an editor, and fail on any error the services log.
The existing tests show the plumbing works; they cannot show that the site's templates, forms,
semantic queries and uploads still work after an upgrade.

**Fixture** (needs the sanitized export from [backups](backups.md)): a *small* one (a few hundred
pages chosen by category, only the images they reference, semantic data rebuilt with `rebuildData.php`)
for every CI run, and a *full* one for the pre-production rehearsal. Not committed (1.2+ GB and
18+ GB): published to object storage with a manifest (hash, MariaDB and MediaWiki/SMW versions) and
passed into the VM from a directory given by `ROPEWIKI_FIXTURE` via `virtualisation.sharedDirectories`,
so nothing is copied into the Nix store. Load it by importing the SQL (simple, slower) before
considering a prebuilt datadir (fast, pinned to one MariaDB major version).

**The test:**
1. Boot the VM on the *currently deployed* revision, import the fixture, start the site.
2. Run the verification suite once as a baseline.
3. `switch-to-configuration` to the new revision (the real upgrade path, `update.php` included).
4. Run the suite again and compare: pages that rendered before still render, with the same text
   where it should not have changed.

**The suite** is Playwright from a second VM node, against `https://machine` (self-signed;
nixpkgs has `playwright-driver.browsers`, so nothing is downloaded). Worth covering first:
anonymous reads of representative pages (canyon, condition, incident, event, vote, list); the map
pages (Leaflet loads, no JS exception, no failed requests); a PageForms form opens and saves; an SMW
`#ask` table and a result-format chart; Sphinx search finds a known page; login with a test account;
an upload with a thumbnail and a PDF upload; `kml_to_gpx.php` on a fixture KML; `robots.txt`;
`Special:Version` and `composer.json` hidden. Record status, console errors, failed requests and
screenshots per page.

**Log scan:** after the suite, fail on PHP `Fatal`/`Warning`/`Deprecated`/`Notice`, exceptions,
MariaDB errors and warnings, nginx `[error]`/`[emerg]` and searchd `FATAL`/`WARNING` in the journal
and the nginx, Sphinx and MariaDB logs. A checked-in allowlist of known benign messages, each with a
reason, keeps it honest. Run it in development mode too, since production mode hides warnings.

Open questions: the size of the small fixture that still catches real regressions (start with about
20 canyons); how often to refresh it; whether CI has the disk and RAM for the full one; who approves
sharing even a sanitized dump.
