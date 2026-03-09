#!/bin/bash
set -euo pipefail

# Fetch static JS/CSS assets from npm and copy them to the webserver directory for serving.

TARGET_DIR="/rw"
TMP_DIR=$(mktemp -d)

echo "Fetching npm packages to $TMP_DIR..."

npm install --prefix "$TMP_DIR" \
    leaflet@1.9.4 \
    leaflet-draw@1.0.4 \
    leaflet-fullscreen@1.0.1 \
    leaflet.vectorgrid@1.3.0

echo "Copying files to $TARGET_DIR..."

# Extract versions from installed packages
LEAFLET_VER=$(node -p "require('$TMP_DIR/node_modules/leaflet/package.json').version")
LEAFLET_DRAW_VER=$(node -p "require('$TMP_DIR/node_modules/leaflet-draw/package.json').version")
LEAFLET_FULLSCREEN_VER=$(node -p "require('$TMP_DIR/node_modules/leaflet-fullscreen/package.json').version")

echo "Installing leaflet@$LEAFLET_VER leaflet-draw@$LEAFLET_DRAW_VER leaflet-fullscreen@$LEAFLET_FULLSCREEN_VER"

# leaflet
mkdir -p "$TARGET_DIR/leaflet/$LEAFLET_VER"
cp -r "$TMP_DIR/node_modules/leaflet/dist/"* "$TARGET_DIR/leaflet/$LEAFLET_VER/"

# leaflet-draw
mkdir -p "$TARGET_DIR/leaflet-draw/$LEAFLET_DRAW_VER"
cp -r "$TMP_DIR/node_modules/leaflet-draw/dist/"* "$TARGET_DIR/leaflet-draw/$LEAFLET_DRAW_VER/"

# leaflet-fullscreen
mkdir -p "$TARGET_DIR/leaflet-fullscreen/$LEAFLET_FULLSCREEN_VER"
cp -r "$TMP_DIR/node_modules/leaflet-fullscreen/dist/"* "$TARGET_DIR/leaflet-fullscreen/$LEAFLET_FULLSCREEN_VER/"

# leaflet.vectorgrid (no version subdirectory)
mkdir -p "$TARGET_DIR/leaflet-vectorgrid"
cp -r "$TMP_DIR/node_modules/leaflet.vectorgrid/dist/"* "$TARGET_DIR/leaflet-vectorgrid/"

echo "Cleaning up..."
rm -rf "$TMP_DIR"

echo "Done! Leaflet assets updated."
