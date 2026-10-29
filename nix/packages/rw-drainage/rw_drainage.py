"""rw-drainage: how much land drains to a point on a stream.

Replaces the `waterflow=winfo=<lat>,<lng>` request of RWServer (the "Luca server"), which the
site's JavaScript uses for the "~N mi2" badge on canyon pages (see nix/docs/drainage.md).

    rw-drainage build  NHDPlus.gdb --out nhdplus.gpkg     make the index (needs GDAL; minutes)
    rw-drainage lookup --index nhdplus.gpkg LAT LNG       one lookup, printed as JSON
    rw-drainage serve  --index nhdplus.gpkg               answer GET /luca/rwr?waterflow=winfo=LAT,LNG

The index is a GeoPackage with one layer, `flowlines`: every NHDPlus V2.1 flowline with its
catchment-network attributes (total drainage area TotDASqKM, Strahler order, stream level).
Looking up a point finds the nearest flowline within 500 m, as RWServer did, and reports its
total drainage area. Serving and looking up need only the Python standard library; building
needs GDAL's Python bindings.
"""

import argparse
import json
import math
import os
import re
import sqlite3
import struct
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

LAYER = "flowlines"
RTREE = f"rtree_{LAYER}_geom"

# RWServer's MINRIVERPOINT: a point farther than this from every river gets no answer.
RADIUS_M = 500
M_PER_DEGREE = 111_195  # a degree of latitude; of longitude it is scaled by cos(latitude)


# --- reading the index --------------------------------------------------------------------


def _wkb_lines(buf, off, out):
    """Append the (lng, lat) vertex lists of the (Multi)LineString at buf[off:] to out.

    Returns the offset after it. Z and M ordinates (ISO and EWKB spellings) are skipped.
    """
    order = "<" if buf[off] == 1 else ">"
    (kind,) = struct.unpack_from(order + "I", buf, off + 1)
    off += 5
    has_z = bool(kind & 0x80000000)
    has_m = bool(kind & 0x40000000)
    kind &= 0x0FFFFFFF
    iso, base = divmod(kind, 1000)
    has_z = has_z or iso in (1, 3)
    has_m = has_m or iso in (2, 3)
    (count,) = struct.unpack_from(order + "I", buf, off)
    off += 4
    if base == 2:  # LineString
        width = 2 + has_z + has_m
        values = struct.unpack_from(f"{order}{count * width}d", buf, off)
        out.append([(values[i], values[i + 1]) for i in range(0, count * width, width)])
        return off + 8 * count * width
    if base == 5:  # MultiLineString
        for _ in range(count):
            off = _wkb_lines(buf, off, out)
        return off
    raise ValueError(f"geometry type {kind} is not a line")


def decode_geometry(blob):
    """The vertex lists of a GeoPackage geometry blob (header, optional envelope, WKB)."""
    if blob[:2] != b"GP":
        raise ValueError("not a GeoPackage geometry")
    flags = blob[3]
    if flags & 0x10:  # empty geometry
        return []
    envelope = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[(flags >> 1) & 7]
    lines = []
    _wkb_lines(blob, 8 + envelope, lines)
    return lines


def distance_m(lines, lat, lng):
    """Distance in metres from (lat, lng) to the nearest point on any of the lines.

    Flat-earth arithmetic around the query point, which is accurate to well under a metre at
    the 500 m this is used for.
    """
    kx = math.cos(math.radians(lat)) * M_PER_DEGREE
    ky = M_PER_DEGREE
    best = math.inf
    for line in lines:
        pts = [((x - lng) * kx, (y - lat) * ky) for x, y in line]
        if len(pts) == 1:
            best = min(best, math.hypot(*pts[0]))
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            dx, dy = bx - ax, by - ay
            length2 = dx * dx + dy * dy
            t = 0.0 if length2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / length2))
            best = min(best, math.hypot(ax + t * dx, ay + t * dy))
    return best


class Index:
    """A read-only handle on an index file. Safe to share between threads."""

    def __init__(self, path):
        self.path = path
        self._local = threading.local()
        try:
            found = self._db().execute("SELECT 1 FROM sqlite_master WHERE name = ?", (RTREE,)).fetchone()
        except sqlite3.DatabaseError:  # missing, or not SQLite at all
            found = None
        if not found:
            raise SystemExit(f"{path} is not an rw-drainage index (no {RTREE}); make one with `rw-drainage build`")

    def _db(self):
        db = getattr(self._local, "db", None)
        if db is None:
            uri = "file:" + self.path.replace("?", "%3f").replace("#", "%23") + "?mode=ro"
            db = self._local.db = sqlite3.connect(uri, uri=True)
        return db

    def lookup(self, lat, lng):
        """The nearest flowline within RADIUS_M of the point, or None.

        {"comid", "drainage_km2" (exact), "stream_order", "stream_level", "distance_m"}
        """
        dlat = RADIUS_M / M_PER_DEGREE
        dlng = dlat / max(math.cos(math.radians(lat)), 1e-6)
        rows = self._db().execute(
            f"""SELECT f.comid, f.totda_km2, f.stream_order, f.stream_level, f.geom
                FROM {RTREE} r JOIN {LAYER} f ON f.fid = r.id
                WHERE r.maxx >= ? AND r.minx <= ? AND r.maxy >= ? AND r.miny <= ?
                  AND f.totda_km2 IS NOT NULL""",
            (lng - dlng, lng + dlng, lat - dlat, lat + dlat),
        )
        best = None
        for comid, area, order, level, geom in rows:
            d = distance_m(decode_geometry(geom), lat, lng)
            if d <= RADIUS_M and (best is None or (d, comid) < (best["distance_m"], best["comid"])):
                best = {
                    "comid": comid,
                    "drainage_km2": area,
                    "stream_order": order,
                    "stream_level": level,
                    "distance_m": d,
                }
        return best


def summary(hit):
    """RWServer's text for a hit, e.g. " O1 L4 Drainage:3.6km2 ".

    RWServer gave whole km2; this gives tenths. The site's JavaScript (before it learned
    `drainage_km2`) cuts the number out of this text between the colon and the next space, so the
    trailing space has to stay.
    """
    parts = []
    if hit["stream_order"]:
        parts.append(f"O{hit['stream_order']}")
    if hit["stream_level"]:
        parts.append(f"L{hit['stream_level']}")
    parts.append(f"Drainage:{hit['drainage_km2']:.1f}km2")
    return " " + " ".join(parts) + " "


def winfo(index, lat, lng):
    """The JSON document answering winfo=lat,lng."""
    hit = index.lookup(lat, lng)
    if hit is None:
        return {"list": []}
    return {
        "list": [summary(hit)],
        # What the page displays: km2 to a tenth.
        "drainage_km2": round(hit["drainage_km2"], 1),
        "comid": hit["comid"],
    }


# --- the HTTP service ---------------------------------------------------------------------

# `waterflow=winfo=34.2,-117.5` is what the page sends (the value of `waterflow` is
# `winfo=...`); RWServer looked for `winfo=` anywhere, so `?winfo=...` works too.
WINFO = re.compile(r"(?:^|&)(?:waterflow=)?winfo=([^&]*)")
LATLNG = re.compile(r"\s*(-?\d+(?:\.\d*)?)\s*,\s*(-?\d+(?:\.\d*)?)\s*$")


def make_handler(index):
    class Handler(BaseHTTPRequestHandler):
        server_version = "rw-drainage"
        sys_version = ""

        def _send(self, status, body, cache=None):
            data = json.dumps(body, separators=(",", ":")).encode() + b"\r\n"
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            # The browser calls this from the wiki's own origin, but dev sites use another.
            self.send_header("Access-Control-Allow-Origin", "*")
            if cache:
                self.send_header("Cache-Control", cache)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(data)

        def do_GET(self):
            path, _, query = self.path.partition("?")
            if path == "/healthz":
                return self._send(200, {"status": "ok"})
            if path.rstrip("/").split("/")[-1] != "rwr":
                return self._send(404, {"error": "not found"})
            found = WINFO.search(query)
            if not found:
                # RWServer's other requests (pdfx=, kmlx=, ...) are not implemented here.
                return self._send(404, {"error": "only waterflow=winfo=<lat>,<lng> is supported"})
            match = LATLNG.match(unquote(found.group(1)))
            lat, lng = (float(v) for v in match.groups()) if match else (math.nan, math.nan)
            if not (-90 <= lat <= 90 and -180 <= lng <= 180):
                return self._send(400, {"error": "winfo must be <lat>,<lng>"})
            # The answer depends only on the point and the index: let browsers and the proxy keep it.
            self._send(200, winfo(index, lat, lng), cache="public, max-age=86400")

        do_HEAD = do_GET

        def log_message(self, fmt, *args):
            sys.stderr.write(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else '?'}\n")

    return Handler


def serve(index, host, port):
    server = ThreadingHTTPServer((host, port), make_handler(index))
    server.daemon_threads = True
    print(f"rw-drainage: serving {index.path} on {host}:{server.server_address[1]}", file=sys.stderr, flush=True)
    server.serve_forever()


# --- making the index ---------------------------------------------------------------------


def build(source, out, flowline_layer, vaa_source, vaa_layer):
    """Write the index `out` from NHDPlus flowlines joined to their value-added attributes."""
    from osgeo import gdal, ogr, osr

    gdal.UseExceptions()
    ogr.UseExceptions()

    def open_layer(path, name):
        ds = ogr.Open(path)
        layer = ds.GetLayerByName(name)
        if layer is None:
            names = [ds.GetLayer(i).GetName() for i in range(ds.GetLayerCount())]
            raise SystemExit(f"{path} has no layer {name!r}; it has: {', '.join(names)}")
        return ds, layer

    def field(layer, name):
        i = layer.GetLayerDefn().GetFieldIndex(name)  # case-insensitive: COMID / ComID
        if i < 0:
            names = [d.GetName() for d in layer.GetLayerDefn().GetFields()]
            raise SystemExit(f"layer {layer.GetName()} has no field {name!r}; it has: {', '.join(names)}")
        return i

    def number(feature, i, cast):
        text = feature.GetFieldAsString(i).strip() if feature.IsFieldSetAndNotNull(i) else ""
        return cast(float(text)) if text else None  # via float: a CSV column is text, "4" or "4.0"

    # A layer is only valid while its dataset is alive, so keep both.
    flowline_ds, flowlines = open_layer(source, flowline_layer)
    vaa_ds, vaa = open_layer(vaa_source or source, vaa_layer)

    v_comid, v_area, v_order, v_level = (field(vaa, n) for n in ("ComID", "TotDASqKM", "StreamOrde", "StreamLeve"))
    attributes = {}
    for f in vaa:
        comid = number(f, v_comid, int)
        if comid is not None:
            attributes[comid] = (number(f, v_area, float), number(f, v_order, int), number(f, v_level, int))
    print(f"{len(attributes)} rows of attributes", file=sys.stderr)

    # Query arithmetic assumes degrees; NHDPlus is NAD83 geographic, which is as good as WGS84 here.
    srs = flowlines.GetSpatialRef()
    transform = None
    if srs is None or not srs.IsGeographic():
        wgs84 = osr.SpatialReference()
        wgs84.ImportFromEPSG(4326)
        wgs84.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
        if srs is not None:
            srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
            transform = osr.CoordinateTransformation(srs, wgs84)
        srs = wgs84

    f_comid = field(flowlines, "COMID")
    tmp = out + ".building.gpkg"  # GDAL wants the extension
    if os.path.exists(tmp):
        os.remove(tmp)
    dest = ogr.GetDriverByName("GPKG").CreateDataSource(tmp)
    layer = dest.CreateLayer(LAYER, srs, ogr.wkbMultiLineString, ["GEOMETRY_NAME=geom", "FID=fid", "SPATIAL_INDEX=YES"])
    for name, kind in [("comid", ogr.OFTInteger64), ("totda_km2", ogr.OFTReal), ("stream_order", ogr.OFTInteger), ("stream_level", ogr.OFTInteger)]:
        layer.CreateField(ogr.FieldDefn(name, kind))

    written = skipped = 0
    layer.StartTransaction()
    for f in flowlines:
        geom = f.GetGeometryRef()
        comid = number(f, f_comid, int)
        if geom is None or comid is None:
            skipped += 1
            continue
        geom = geom.Clone()
        if transform:
            geom.Transform(transform)
        geom.FlattenTo2D()
        area, order, level = attributes.get(comid, (None, None, None))
        row = ogr.Feature(layer.GetLayerDefn())
        row.SetGeometry(ogr.ForceToMultiLineString(geom))
        row.SetField("comid", comid)
        for name, value in (("totda_km2", area), ("stream_order", order), ("stream_level", level)):
            if value is not None:
                row.SetField(name, value)
        layer.CreateFeature(row)
        written += 1
        if written % 200_000 == 0:
            layer.CommitTransaction()
            layer.StartTransaction()
            print(f"{written} flowlines", file=sys.stderr, flush=True)
    layer.CommitTransaction()
    layer = dest = flowline_ds = vaa_ds = None  # closing the file creates the spatial index
    os.replace(tmp, out)
    print(f"{out}: {written} flowlines ({skipped} skipped)", file=sys.stderr)


# --- command line -------------------------------------------------------------------------


def main(argv=None):
    parser = argparse.ArgumentParser(prog="rw-drainage", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)

    b = sub.add_parser("build", help="make an index from NHDPlus V2.1 data")
    b.add_argument("source", help="the NHDPlus seamless geodatabase (.gdb) or any OGR source with both layers")
    b.add_argument("--out", required=True, help="index file to write")
    b.add_argument("--flowline-layer", default="NHDFlowline_Network")
    b.add_argument("--vaa-source", help="where the attribute table is, if not in SOURCE (e.g. a CSV)")
    b.add_argument("--vaa-layer", default="PlusFlowlineVAA")

    look = sub.add_parser("lookup", help="look one point up")
    look.add_argument("--index", required=True)
    look.add_argument("lat", type=float)
    look.add_argument("lng", type=float)

    s = sub.add_parser("serve", help="answer winfo requests over HTTP")
    s.add_argument("--index", required=True)
    s.add_argument("--host", default="127.0.0.1")
    s.add_argument("--port", type=int, default=9002)

    args = parser.parse_args(argv)
    if args.command == "build":
        build(args.source, args.out, args.flowline_layer, args.vaa_source, args.vaa_layer)
    elif args.command == "lookup":
        print(json.dumps(winfo(Index(args.index), args.lat, args.lng), indent=1))
    else:
        serve(Index(args.index), args.host, args.port)


if __name__ == "__main__":
    main()
