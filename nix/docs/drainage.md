# Drainage area (the Luca server's waterflow lookup)

See [TODO](../TODO.md). Replaces one of the two things the [Luca server](luca-server.md) still did
for the site. Code: `packages/rw-drainage.nix` and `packages/rw-drainage/`, module
`modules/drainage.nix`, tests `tests/drainage*.nix`.

## What the feature is

On a US or Canada canyon page, the infobox's Weather row has a `[gauge] Waterflow` link followed by
`~N mi²` (`~N km²` in metric): roughly how much land drains to the canyon. Above 25, 50 and 100 km²
it adds a flood-warning icon. It is not the Waterflow page itself: that link goes to `/Waterflow`,
whose `Waterflow.js` reads USGS gauges through a Cloudflare worker and never touched the Luca server.

`ui.js` in commonjs asks the Luca server for it:

    GET https://ropewiki.com/luca/rwr?waterflow=winfo=34.2533,-117.5769      (lat,lng)

RWServer looked the point up in river tiles scraped from the EPA's NHDPlus V2.1 services and
answered with the nearest river segment within 500 m:

    {"list":[" O1 L4 Drainage:4km2 AvgFlow:4cfs AvgPrecip:1157mm AvgTemp:9C <a href='...pComID=22554664' ...>[Full Report]</a>"]}

`22554664` is the NHDPlus COMID; `Drainage` is the segment's cumulative drainage area in km², `O`
its Strahler order and `L` its stream level. The page reads only the `Drainage:` number. Canadian
pages get `{"list":["O2"]}` (no area), so no badge. The EPA service the tiles came from is gone, so
those numbers are a years-old snapshot nobody can refresh.

## What replaces it

Same request, same URL (`/luca/rwr`, proxied by nginx to a Python service on 127.0.0.1:9002), same
nearest-within-500 m rule, with data that can be rebuilt: **NHDPlus V2.1** flowlines
(`NHDFlowline_Network`) joined to the value-added attributes (`PlusFlowlineVAA`: `TotDASqKM`,
`StreamOrde`, `StreamLeve`). It is the same dataset, so the numbers should agree. US only, as before
(the national geodatabase is the lower 48; Alaska, Hawaii and Puerto Rico are separate downloads).

The answer is `{"list":[" O1 L4 Drainage:3.6km2 "],"drainage_km2":3.6,"comid":22554664}` (the number
is made up; production gave whole km², `4`), or `{"list":[]}` when no river is within 500 m. Not
carried over: average flow, precipitation and temperature (the page never showed them) and the link
to the EPA report (the service is gone). Nothing else of RWServer is served: `pdfx=` and the rest
answer 404.

- **Tenths.** The area is given to a tenth of a km² (RWServer: whole km²). The badge is a `udrain`
  span holding the exact km² in `data-km2`; `convertUnitElements` redraws it from that when the
  visitor switches units, so toggling never compounds rounding. Flood icons use the exact value.
- **Text and number.** `packages/site-pages-drainage.patch` makes `ui.js` read the `drainage_km2`
  number. The text keeps RWServer's format, with a space after the number, because the old
  `extractVal` gets `NaN` when the number ends the string (a browser with a cached `Common.js`, or
  any other site). The patch also fixes that case.
- **The Luca host.** `packages/site-pages-luca-host.patch` makes `constants.js` always call
  `<the page's own host>/luca`; it had a hostname list (production and the co-op sites
  `ropewiki.com/luca`, `localhost:8080` a hardcoded AWS IP). Now a VM, test site or mirror calls its
  own server, so **the web server must route `/luca`**: the Nix module does; in the Docker setup
  only `reverse_proxy/services.conf` does, so a Docker dev site not behind it gets no badge (and no
  PDF export) where it used to reach production through the IP. Both patches should go upstream into
  commonjs; then delete them and `applyPatches` in `site-pages.nix`.

## The index and where the data comes from

`rw-drainage build` writes a GeoPackage, `flowlines`, with the comid, area, order, level and the
line (2D, MultiLineString) with an R-tree index. Serving needs only the Python standard library
(`sqlite3` plus a small WKB reader); GDAL is used only to build. A lookup reads the few lines whose
bounding box touches the 500 m box and takes the nearest, in about a millisecond.

The data is downloaded **at runtime, on the host, once**, not at build time and not into the Nix
store (a fixed-output `fetchurl` would put 7.8 GB, its extraction and the index into the store of
every machine and CI runner that evaluates the flake, for a file that never changes). With
`services.ropewiki.drainage.enable` and the default `sourceUrl`, `rw-drainage-index.service` runs
when `/var/lib/rw-drainage/nhdplus.gpkg` does not exist:

1. `curl --continue-at -` fetches the EPA's `NHDPlusV21_NationalData_Seamless_Geodatabase_Lower48_07.7z`
   (7.8 GB, public S3 bucket, no login). A failure ends the unit and, ten minutes later, the retry
   resumes the same file.
2. `7zz` extracts it (several times larger) and the archive is deleted.
3. `rw-drainage build` reads the `.gdb` and writes the index; the work directory is deleted.

Peak disk is about 25 GB under `/var/lib/rw-drainage`, and the builder holds the 2.7 million row
attribute table in memory (a few GB). `rw-drainage.path` starts the server when the index appears;
until then nginx answers 502 and the page shows no badge. To rebuild, delete the file and start the
unit. To build elsewhere, run `rw-drainage build` there and set `index` to the file with
`sourceUrl = null`.

```nix
services.ropewiki.drainage.enable = true;     # needs services.ropewiki.enable
# services.ropewiki.drainage.sourceUrl = null;  # and set .index to a file you built
```

By hand: `rw-drainage build NHDPlusV21_National_Seamless_Flattened_Lower48.gdb --out nhdplus.gpkg`
then `rw-drainage lookup --index nhdplus.gpkg 34.2533 -117.5769`.

## What is not tested

- **The real data.** The fixtures are three flowlines: Lytle Creek (Middle Fork), whose geometry is
  the real one (USGS NLDI) and whose area, 3.6 km², is made up, and two invented rivers. The layer
  and field names (`NHDFlowline_Network`, `PlusFlowlineVAA`, `ComID`, `TotDASqKM`, `StreamOrde`,
  `StreamLeve`) are from NHDPlus V2.1's documentation, not from opening the download. **Before
  relying on it, build the real index and check that `rw-drainage lookup 34.2533 -117.5769` says
  comid 22554664 and an area that rounds to 4,** then compare a few hundred canyon coordinates from
  the wiki with the live site's answers. If a name is wrong, `build` lists the layers or fields that exist.
- **The badge in a browser.** The display code (tenths, unit toggling, the Luca host) was checked
  once with Node against the patched sources; there is no permanent test for it.

Open: Alaska, Hawaii, Puerto Rico and Canada have no badge; and whether to precompute the value into
a Semantic MediaWiki property (it depends only on the page's coordinates) and drop the service, which
touches the templates and needs a bot run.
