<?php
/**
 * KML to GPX Converter
 * 
 * It takes a "url" parameter from the GET request. The url is converted
 * into a local path and checked to ensure it exists and is in the expected location.
 * It then converts the KML file to GPX format using the gpsbabel command line tool.
 * The converted GPX file is returned as a downloadable response.
 * 
 * Requirements:
 * - gpsbabel must be installed and accessible on the server.
 * - PHP shell_exec() and passthru() functions must be enabled.
 */

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405); // Method Not Allowed
    echo json_encode(['error' => 'HTTP 405 - Method Not Allowed']);
    exit;
}

// Check if "url" parameter is provided in GET request
if (empty($_GET['url'])) {
    http_response_code(400);
    echo json_encode(['error' => 'URL parameter is required']);
    exit;
}

// Because mediawiki is infuriating we have to pass in "url", but we
// strip off the domain, and tweak it to match the real path on the server.
// We never actually fetch the URL, we just use it to get the path.

$parsedUrl = parse_url($_GET['url']);
$path = $parsedUrl['path'];
$realpath = realpath('/rw' . $path);

// Check the path is fully resolved, exists, and is in the expected location.
if ($realpath === false || strpos($realpath, '/usr/share/nginx/html/ropewiki/images/') !== 0) {
    http_response_code(400);
    echo json_encode(['error' => 'Error checking file path '. $realpath]);
    exit;
}

header('Content-Type: application/gpx+xml');
header('Content-Disposition: attachment; filename="' . basename($realpath, '.kml') . '.gpx"');

$command = escapeshellcmd("/usr/bin/gpsbabel -i kml -f $realpath -o gpx -F -");
passthru($command, $returnVar);

if ($returnVar !== 0) {
    http_response_code(500);
    echo json_encode(['error' => 'Conversion failed']);
}
