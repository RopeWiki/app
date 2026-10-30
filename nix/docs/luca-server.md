# The Luca server (RWServer)

See [TODO](../TODO.md) for the checklist.

## What it is and who talks to it

RWServer (`ropewiki-RWServer`, https://github.com/RopeWiki/RWServer) is a Windows/MSVC FastCGI
program, `rw.exe`/`rwr.exe`, about 90k lines of C++ on MFC. In production it runs on a separate
**Windows host on AWS** (the RWServer README says so; the reverse proxy allow-lists its address,
`3.87.207.135`, which falls in Amazon's `3.80.0.0/12`). `reverse_proxy/services.conf` forwards
`/luca` to it. Its own nginx passes requests by FastCGI to port 9001.

The wiki server never calls it. The visitor's browser does, through the site's JavaScript
(`commonjs`): `<site>/luca/rwr?...`, with `Access-Control-Allow-Origin: *` on the responses. The
server in turn fetches `ropewiki.com/PDFList` and `PDFScript` and drives `phantomjs.exe` to
render PDFs, and its command-line modes (`-setpics`, `-uploadbeta*`, waterflow site updates) log in
to the wiki with bot credentials; those are batch jobs, not the daemon.

## What the site still uses it for

Two features, found by reading the site's JavaScript (`commonjs`):
- **PDF export** (`pdfx=`, `lib/pdf.js`), and
- the **drainage-area badge** ("~N mi²" in the infobox; `waterflow=winfo=`, `lib/ui/ui.js`). This
  one still works in production (checked 2026-10-29) and is replaced; see [drainage.md](drainage.md).

GPX export moved into this repo's `kml_to_gpx.php`, and the picture lookup is commented out.
What the repositories can't show: wiki content in the database (the `{{RWServerUrl}}` template, the
`PDFScript`/`PDFList` pages, `MediaWiki:Common.js`). **To settle PDF export, count `/luca` hits in
the production reverse-proxy access log.**

## Decision

The Nix flake does **not** run it. The most likely outcome is to **re-implement the two features
as new, independent projects** rather than keep an MFC program alive: the drainage lookup is done
(`services.ropewiki.drainage`, [drainage.md](drainage.md), a small Python service over NHDPlus);
PDF export is still to do (headless Chromium instead of the long-dead PhantomJS).

A stop-gap was built and tested (a `services.ropewiki.rwserver` module that ran a prebuilt
`rwr.exe` under Wine behind nginx `location /luca/ { fastcgi_pass 127.0.0.1:9001; }`, with a
cross-compiled stand-in executable for the VM test) and then removed again to keep the flake
small. What it taught us, if it is ever wanted again:
- RWServer publishes **no binary**: no releases, and its GitHub Actions artifacts expire and need
  auth. The Release build (static MFC and CRT, so no redistributable) has to be built on Windows.
- It reads **data that isn't in its repository** (e.g. `poi\iprogress.htm`, the RopeWiki Explorer
  data) and has **secrets compiled in** via `passwords.h`.
- It binds `0.0.0.0:9001` itself, so that port must stay firewalled.
- The support files that sit next to the executable (DLLs, `phantomjs.exe`/`phantomjs.js`, the
  `wf/` waterflow data, 32 MB) are all in its repository.
- PhantomJS under Wine was never tested; the VM test only used the stand-in.
