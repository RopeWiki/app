"""Tests for rw_drainage, run by the package's check phase (RW_DRAINAGE_FIXTURES names fixtures/)."""

import json
import os
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

import rw_drainage

FIXTURES = os.environ["RW_DRAINAGE_FIXTURES"]

# The point from the production example: Lytle Creek (Middle Fork), where RWServer answered
# " O1 L4 Drainage:4km2 ..." for comid 22554664 (whole km2; this service gives tenths).
LYTLE = (34.2533, -117.5769)


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.path = os.path.join(cls.tmp.name, "index.gpkg")
        # The attributes come from a CSV here and from a table in the .gdb for real data.
        rw_drainage.build(
            os.path.join(FIXTURES, "flowlines.geojson"),
            cls.path,
            "NHDFlowline_Network",
            os.path.join(FIXTURES, "vaa.csv"),
            "vaa",
        )
        cls.index = rw_drainage.Index(cls.path)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()


class Lookup(Base):
    def test_finds_the_nearest_flowline_not_the_biggest(self):
        # a 400 km2 river is also within 500 m, but Lytle Creek is nearer
        hit = self.index.lookup(*LYTLE)
        self.assertEqual(hit["comid"], 22554664)
        self.assertEqual((hit["stream_order"], hit["stream_level"]), (1, 4))
        self.assertAlmostEqual(hit["drainage_km2"], 3.6)
        self.assertLess(hit["distance_m"], 250)

    def test_text_is_what_rwserver_sent(self):
        self.assertEqual(rw_drainage.summary(self.index.lookup(*LYTLE)), " O1 L4 Drainage:3.6km2 ")

    def test_areas_are_given_to_a_tenth(self):
        # 400.2 and 4321.5 are in the fixture; neither is a whole number
        hit = self.index.lookup(34.3, -117.5)
        self.assertEqual(rw_drainage.summary(hit), " O7 L2 Drainage:4321.5km2 ")
        for area, text in [(3.64, "3.6"), (3.66, "3.7"), (4.0, "4.0"), (0.04, "0.0")]:
            self.assertIn(f"Drainage:{text}km2", rw_drainage.summary({**hit, "drainage_km2": area}))

    def test_winfo_document(self):
        self.assertEqual(
            rw_drainage.winfo(self.index, *LYTLE),
            {"list": [" O1 L4 Drainage:3.6km2 "], "drainage_km2": 3.6, "comid": 22554664},
        )

    def test_the_radius_is_500_metres(self):
        # the made-up river runs along latitude 34.3; 0.0040 degrees is 445 m, 0.0050 is 556 m
        self.assertEqual(self.index.lookup(34.3 + 0.0040, -117.5)["comid"], 900000002)
        self.assertIsNone(self.index.lookup(34.3 + 0.0050, -117.5))

    def test_beyond_the_end_of_a_line_counts_from_its_end(self):
        # the line ends at -117.495; 0.004 degrees of longitude is 367 m at this latitude
        self.assertEqual(self.index.lookup(34.3, -117.495 + 0.004)["comid"], 900000002)
        self.assertIsNone(self.index.lookup(34.3, -117.495 + 0.007))

    def test_nothing_nearby(self):
        self.assertEqual(rw_drainage.winfo(self.index, 40.0, -100.0), {"list": []})
        self.assertEqual(rw_drainage.winfo(self.index, 0.0, 0.0), {"list": []})

    def test_the_index_has_exactly_what_was_given(self):
        rows = self.index._db().execute(f"SELECT comid, totda_km2 FROM {rw_drainage.LAYER} ORDER BY comid").fetchall()
        self.assertEqual(rows, [(22554664, 3.6), (900000001, 400.2), (900000002, 4321.5)])

    def test_a_file_that_is_not_an_index_is_refused(self):
        with self.assertRaises(SystemExit):
            rw_drainage.Index(os.path.join(FIXTURES, "vaa.csv"))


class Http(Base):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), rw_drainage.make_handler(cls.index))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        super().tearDownClass()

    def get(self, path):
        try:
            with urllib.request.urlopen(self.base + path) as response:
                return response.status, response.headers, response.read()
        except urllib.error.HTTPError as e:
            with e:
                return e.code, e.headers, e.read()

    def test_the_request_the_page_sends(self):
        status, headers, body = self.get("/luca/rwr?waterflow=winfo=34.2533,-117.5769")
        self.assertEqual(status, 200)
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(headers["Access-Control-Allow-Origin"], "*")
        doc = json.loads(body)
        self.assertEqual(doc["list"], [" O1 L4 Drainage:3.6km2 "])
        self.assertEqual(doc["drainage_km2"], 3.6)

    def test_the_old_javascript_can_still_read_it(self):
        # ui.js extractVal(str, 'Drain'): from the colon to the next space, then parseInt
        text = json.loads(self.get("/luca/rwr?waterflow=winfo=34.2533,-117.5769")[2])["list"][0]
        colon = text.index(":", text.index("Drain"))
        end = text.find(" ", colon)
        self.assertGreater(end, 0, "no space after the number: parseInt would get NaN in the browser")
        self.assertEqual(float(text[colon + 1 : end].removesuffix("km2")), 3.6)

    def test_other_spellings_of_the_same_request(self):
        for path in [
            "/luca/rwr?winfo=34.2533,-117.5769",
            "/rwr?waterflow=winfo=34.2533%2C-117.5769",
            "/luca/rwr?foo=1&waterflow=winfo=34.2533,%20-117.5769&bar=2",
        ]:
            status, _, body = self.get(path)
            self.assertEqual((status, json.loads(body)["comid"]), (200, 22554664), path)

    def test_no_river_is_an_empty_list(self):
        status, _, body = self.get("/luca/rwr?waterflow=winfo=40,-100")
        self.assertEqual((status, json.loads(body)), (200, {"list": []}))

    def test_bad_coordinates(self):
        for value in ["", "abc", "34.2", "34.2,", "91,0", "0,181", "nan,0", "1,2,3"]:
            self.assertEqual(self.get(f"/luca/rwr?waterflow=winfo={value}")[0], 400, value)

    def test_rwserver_requests_that_are_not_implemented(self):
        for path in ["/luca/rwr?pdfx=Lytle_Creek", "/luca/rwr", "/luca/other?winfo=34,-117", "/"]:
            self.assertEqual(self.get(path)[0], 404, path)

    def test_health(self):
        self.assertEqual(self.get("/healthz")[0], 200)


if __name__ == "__main__":
    unittest.main()
