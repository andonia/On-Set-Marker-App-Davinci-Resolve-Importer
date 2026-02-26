#!/bin/bash
# DaVinci Resolve Marker Importer — installer
set -e

SCRIPT="marker_importer.lua"

# Resolve script directories (in priority order)
USER_DIR="$HOME/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"
SYSTEM_DIR="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility"

if [ ! -f "$SCRIPT" ]; then
    echo "Error: $SCRIPT not found. Run this script from the same folder as $SCRIPT."
    exit 1
fi

# Install to user directory (no sudo required)
mkdir -p "$USER_DIR"
cp "$SCRIPT" "$USER_DIR/$SCRIPT"

echo "Installed: $USER_DIR/$SCRIPT"
echo ""
echo "In DaVinci Resolve, run via:"
echo "  Workspace ▸ Scripts ▸ Utility ▸ marker_importer"
