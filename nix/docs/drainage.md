# Drainage area (the Luca server's waterflow lookup)

Part of the Nix migration; see [TODO](../TODO.md). Replaces one of the two things the
[Luca server](luca-server.md) still did for the site. Code: `packages/rw-drainage.nix` and
`packages/rw-drainage/`, module `modules/drainage.nix`, tests `tests/drainage*.nix`.

## What the feature is

On a US or Canada canyon page, the infobox's Weather row has a `[gauge] Waterflow` link followed by
`~N mi²` (`~N km²` in metric): roughly how much land drains to the canyon. Above 25, 50 and 100 km²
it adds a flood-warning icon ("May flood during heavy rains..."). It is not the Waterflow page
itself: that link goes to `/Waterflow`, whose `Waterflow.js` reads USGS gauges through a Cloudflare
worker and never touched the Luca server.

`ui.js` in commonjs asks the Luca server for it:

    GET https://ropewiki.com/luca/rwr?waterflow=winfo=34.2533,-117.5769      (lat,lng)

RWServer looked the point up in river tiles (`POI/RIVERS*`) that it had scraped from the EPA's
NHDPlus V2.1 services and answered with the nearest river segment within 500 m:

    {"list":[" O1 L4 Drainage:4km2 AvgFlow:4cfs AvgPrecip:1157mm AvgTemp:9C <a href='http://ofmpub.epa.gov/waters10/watershed_characterization.control?pComID=22554664' ...>[Full Report]</a>"]}

`22554664` is the NHDPlus COMID; `Drainage` is the segment's cumulative drainage area in km²
(`cumdrainag`), `O` its Strahler order and `L` its stream level. The page reads only the
`Drainage:` number. Canadian pages get `{"list":["O2"]}` (order only, no area), so no badge: the
tiles for Canada came from other data and never had drainage areas. The EPA service the tiles were
scraped from is gone, so the numbers are a years-old snapshot nobody can refresh.

## What replaces it

Same request, same URL (`/luca/rwr`, proxied by nginx to a Python service on 127.0.0.1:9002), same
nearest-within-500 m rule, with data that can be rebuilt: **NHDPlus V2.1** flowlines
(`NHDFlowline_Network`) joined to the value-added attributes (`PlusFlowlineVAA`: `TotDASqKM`,
`StreamOrde`, `StreamLeve`). It is the same dataset, so the numbers should agree with the old ones.
US only, as before (the national geodatabase is the lower 48; Alaska and Hawaii are separate
downloads and not included).

The answer is `{"list":[" O1 L4 Drainage:3.6km2 "],"drainage_km2":3.6,"comid":22554664}` (the
number here is made up; production gave whole km², `4`), or
`{"list":[]}` when no river is within 500 m. Not carried over: average flow, precipitation and
temperature (the page never showed them) and the link to the EPA report (the service is gone).

- **Tenths.** The area is given to a tenth of a km² (RWServer: whole km²), and the page shows it
  that way, `~3.6km²` or `~1.4mi²`. The badge is a `udrain` span holding the exact km² in
  `data-km2`; `convertUnitElements` redraws it from that when the visitor switches units, so
  toggling never compounds rounding (the older `umi2` class re-rounds to two significant digits).
  Flood icons still use the exact value (over 25, 50, 100 km²).
- **Text and number.** `packages/site-pages-drainage.patch` makes `ui.js` read the `drainage_km2`
  number. The text format stays RWServer's, with a space after the number, because the old
  `extractVal` cuts the number out between the colon and the next space and gets `NaN` when the
  number ends the string (a browser with a cached `Common.js`, or any other site). The patch also
  fixes that case.
- **The Luca host.** `packages/site-pages-luca-host.patch` makes `constants.js` always call
  `<the page's own host>/luca`. It had a list of hostnames: production used `ropewiki.com/luca`,
  `localhost:8080` a hardcoded IP of the AWS server, the co-op sites `ropewiki.com/luca`. Now a VM,
  a test site or a mirror calls its own server. **The web server must route `/luca`:** the Nix
  module does (this service); in the Docker setup only `reverse_proxy/services.conf` does, so a
  Docker dev site that is not behind it gets no badge (and no PDF export) where it used to reach
  production through the IP. Both patches should go upstream into commonjs; then delete them and
  `applyPatches` in `site-pages.nix`.
- **Nothing else of RWServer is served.** `pdfx=` and the rest answer 404 from this service.
  PDF export is a separate project (see [luca-server.md](luca-server.md)).

## The index

`rw-drainage build` writes a GeoPackage, `flowlines`, with the comid, area, order, level and the
line (2D, MultiLineString) with an R-tree index. Serving needs only the Python standard library
(`sqlite3` plus a small WKB reader); GDAL is used only to build. A lookup reads the few lines whose
bounding box touches the 500 m box, takes the nearest and reports it. About a millisecond.

With `services.ropewiki.drainage.enable` and the default `sourceUrl`, `rw-drainage-index.service`
downloads the EPA's 7.8 GB archive, extracts it, builds the index into
`/var/lib/rw-drainage/nhdplus.gpkg` and removes the work files (needs about 25 GB of disk while it
runs and several GB of RAM for the attribute table). It runs once, in the background, when the
index does not exist; `rw-drainage.path` starts the server when the file appears. To rebuild, delete
the file and start the unit. Until then nginx answers 502 and the page shows no badge.

```nix
services.ropewiki.drainage.enable = true;     # needs services.ropewiki.enable
# services.ropewiki.drainage.sourceUrl = null;  # and set .index to a file you built
```

By hand: `rw-drainage build NHDPlusV21_National_Seamless_Flattened_Lower48.gdb --out nhdplus.gpkg`
then `rw-drainage lookup --index nhdplus.gpkg 34.2533 -117.5769`.

## Getting the data

It is downloaded **at runtime, on the host, once**, not at build time and not into the Nix store.
`rw-drainage-index.service` (in `modules/drainage.nix`) runs when `index` does not exist:

1. `curl --continue-at -` fetches `sourceUrl`, the EPA's `NHDPlusV21_NationalData_Seamless_Geodatabase_Lower48_07.7z`
   (7.8 GB, public S3 bucket, no login). A failure ends the unit and, ten minutes later, the retry
   resumes the same file.
2. `7zz` extracts it (the geodatabase is several times larger) and the archive is deleted.
3. `rw-drainage build` reads the `.gdb` and writes the index; the work directory is deleted.

Peak disk is about 25 GB under `/var/lib/rw-drainage` and the builder holds the attribute table
(2.7 million rows) in memory, a few GB. The index that stays is small compared to that (the line
geometry and four numbers per flowline; I have not measured it). Nothing is ever downloaded again
unless you delete the index.

Why not at build time: a fixed-output derivation (`fetchurl` with a hash) would put 7.8 GB, its
extraction and the index into the Nix store of every machine and CI runner that evaluates the
flake, for a file that never changes. If a build host with more room should do the work, run
`rw-drainage build` there and ship the index (`index = ./nhdplus.gpkg` or a path copied to the
host; `sourceUrl = null`), or serve it from a binary cache as a derivation of your own.

## What is tested, and what is not

- `nix build .#rw-drainage` (also a flake check) runs the unit tests: the builder on fixtures,
  nearest-not-biggest, the 500 m edge, the end of a line, coordinate spellings, bad input, and that
  the text still parses the way `extractVal` does.
- `checks.drainage`: the service behind the site's nginx, the 502 before the index exists, start
  when it appears, loopback only, the patched `Common.js` published.
- `checks.drainage-index`: the downloader, with a made-up archive in the layout of the EPA's
  (a `.gdb` with both layers) served through `file://`, including rebuilding.
- **Not tested: the real data.** The fixtures are three flowlines: Lytle Creek (Middle Fork), whose
  geometry is the real one (USGS NLDI) and whose area, 3.6 km², is made up (production's whole-km²
  answer is 4), and two invented rivers. The layer and field names (`NHDFlowline_Network`,
  `PlusFlowlineVAA`, `ComID`, `TotDASqKM`, `StreamOrde`, `StreamLeve`) are from NHDPlus V2.1's
  documentation, not from opening the download. **Before relying on it, build the real index and
  check that `rw-drainage lookup 34.2533 -117.5769` says comid 22554664 and an area that
  rounds to 4,** then compare a
  few hundred canyon coordinates from the wiki against the live site's answers. If a name is
  wrong, `build` lists the layers or fields that exist and exits.
- The badge in a browser is not tested (no headless browser in the VM tests). The display code
  (tenths, unit toggling without drift, the Luca host for several host names) was checked once
  with Node against the patched sources; there is no permanent test for it.

## Left open

- Alaska, Hawaii and Puerto Rico (separate NHDPlus downloads) and Canada (no source, no previous
  data) have no badge.
- Whether to precompute the value into a Semantic MediaWiki property (it depends only on the
  page's coordinates) and drop the service. More invasive: touches the templates and needs a bot
  run. Possible later.
