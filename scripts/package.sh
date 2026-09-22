#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PLUGIN_NAME="readwisereader.koplugin"
PLUGIN_DIR="$ROOT_DIR/$PLUGIN_NAME"
DIST_DIR="$ROOT_DIR/dist"
OUT="$DIST_DIR/$PLUGIN_NAME.zip"

[ -f "$PLUGIN_DIR/_meta.lua" ] || {
    printf '%s\n' "package: missing $PLUGIN_NAME/_meta.lua" >&2
    exit 1
}
[ -f "$PLUGIN_DIR/main.lua" ] || {
    printf '%s\n' "package: missing $PLUGIN_NAME/main.lua" >&2
    exit 1
}
command -v zip >/dev/null 2>&1 || {
    printf '%s\n' "package: zip command not found" >&2
    exit 1
}

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

(
    cd "$ROOT_DIR"
    zip -qr "$OUT" "$PLUGIN_NAME" \
        -x "$PLUGIN_NAME/tests/private/*" \
        -x "$PLUGIN_NAME/*.tmp"
)

printf '%s\n' "package: $OUT"
