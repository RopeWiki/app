<?php
/**
 * KML to GPX Converter
 * 
 * This PHP script accepts a POST request with a `file_path` parameter pointing to a KML file.
 * It validates that the file path starts with "/images" and sanitizes the input to prevent
 * potential security issues. The script uses gpsbabel to convert the KML file to GPX format 
 * and outputs the result directly as the HTTP response with appropriate headers for file download.
 * 
 * Requirements:
 * - gpsbabel must be installed and accessible on the server.
 * - PHP shell_exec() and passthru() functions must be enabled.
 */

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405); // Method Not Allowed
    echo json_encode(['error' => 'HTTP 405 - Method Not Allowed']);
    exit;
}

$inputFile = isset($_POST['file_path']) ? realpath($_POST['file_path']) : '';

// Check if file path is valid, sanitized, and starts with "/images"
if (empty($inputFile) || strpos($inputFile, realpath('/images')) !== 0 || !file_exists($inputFile)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid or unauthorized file path']);
    exit;
}

header('Content-Type: application/gpx+xml');
header('Content-Disposition: attachment; filename="' . basename($inputFile, '.kml') . '.gpx"');

$command = escapeshellcmd("gpsbabel -i kml -f $inputFile -o gpx -F -");
passthru($command, $returnVar);

if ($returnVar !== 0) {
    http_response_code(500);
    echo json_encode(['error' => 'Conversion failed']);
}
