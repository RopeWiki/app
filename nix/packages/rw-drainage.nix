# rw-drainage: the drainage-area lookup behind the "~N mi2" badge on canyon pages, replacing the
# `waterflow=winfo=` request of the Luca server (RWServer). See nix/docs/drainage.md.
#
#   rw-drainage build  NHDPlus.gdb --out nhdplus.gpkg     once, from the EPA's NHDPlus V2.1 download
#   rw-drainage serve  --index nhdplus.gpkg               what services.ropewiki.drainage runs
#   rw-drainage lookup --index nhdplus.gpkg 34.2533 -117.5769
#
# Building the package runs the tests (tests.py) against the small data set in
# rw-drainage/fixtures; `passthru.fixtureIndex` is the index built from it, for the VM test.
{
  lib,
  stdenvNoCC,
  runCommand,
  makeWrapper,
  python3,
  gdal,
  _7zz,
}:

let
  # Only `build` needs GDAL; the Python process serving requests uses the standard library alone.
  python = python3.withPackages (ps: [ ps.gdal ]);
  src = lib.fileset.toSource {
    root = ./rw-drainage;
    fileset = ./rw-drainage;
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "rw-drainage";
  version = "0.1";
  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm644 rw_drainage.py $out/lib/rw-drainage/rw_drainage.py
    makeWrapper ${python}/bin/python3 $out/bin/rw-drainage \
      --add-flags "-I $out/lib/rw-drainage/rw_drainage.py"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    PYTHONDONTWRITEBYTECODE=1 RW_DRAINAGE_FIXTURES=$src/fixtures ${python}/bin/python3 -m unittest discover -v -s $src -p 'test_*.py'
    $out/bin/rw-drainage --help > /dev/null
    runHook postInstallCheck
  '';

  passthru.fixtureIndex =
    runCommand "rw-drainage-fixture-index.gpkg" { nativeBuildInputs = [ finalAttrs.finalPackage ]; }
      ''
        rw-drainage build ${src}/fixtures/flowlines.geojson --out $out \
          --vaa-source ${src}/fixtures/vaa.csv --vaa-layer vaa
      '';

  # The fixtures in the shape of the EPA's download, for testing the downloader: a 7z holding a
  # geodatabase with NHDFlowline_Network and PlusFlowlineVAA. A dummy; the real one has 2.7 million
  # flowlines and no way to be tested here.
  passthru.fixtureArchive =
    runCommand "rw-drainage-fixture-archive"
      {
        nativeBuildInputs = [
          gdal
          _7zz
        ];
      }
      ''
        gdb=tree/NHDPlusNationalData/NHDPlusV21_National_Seamless_Flattened_Lower48.gdb
        mkdir -p $(dirname $gdb)
        ogr2ogr -f OpenFileGDB $gdb ${src}/fixtures/flowlines.geojson -nln NHDFlowline_Network
        ogr2ogr -f OpenFileGDB -update $gdb ${src}/fixtures/vaa.csv -nln PlusFlowlineVAA -oo AUTODETECT_TYPE=YES
        mkdir $out
        7zz a -t7z $out/nhdplus.7z tree > /dev/null
      '';

  meta = {
    description = "Upstream drainage area of a point on a US stream, from NHDPlus V2.1";
    mainProgram = "rw-drainage";
    platforms = lib.platforms.linux;
  };
})
