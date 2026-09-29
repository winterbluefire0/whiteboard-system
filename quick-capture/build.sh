#!/bin/bash
set -euo pipefail
capture_source="$(cd "$(dirname "$0")" && pwd)"
capture_root="$(dirname "$capture_source")"
capture_bundle="$capture_source/Whiteboard Capture.app"
mkdir -p "$capture_bundle/Contents/MacOS" "$capture_bundle/Contents/Resources"
cp "$capture_source/Info.plist" "$capture_bundle/Contents/Info.plist"
printf '%s\n' "$capture_root" > "$capture_bundle/Contents/Resources/workspace.txt"
capture_binary="$capture_bundle/Contents/MacOS/WhiteboardCapture"
/usr/bin/clang -fobjc-arc "$capture_source/main.m" -framework Cocoa -framework Carbon -o "$capture_binary.new"
mv "$capture_binary.new" "$capture_binary"
printf 'Built: %s\n' "$capture_bundle"
