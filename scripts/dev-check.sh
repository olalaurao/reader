#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PLUGIN_DIR="$ROOT_DIR/readwisereader.koplugin"

fail() {
    printf '%s\n' "dev-check: $*" >&2
    exit 1
}

[ -f "$PLUGIN_DIR/_meta.lua" ] || fail "missing readwisereader.koplugin/_meta.lua"
[ -f "$PLUGIN_DIR/main.lua" ] || fail "missing readwisereader.koplugin/main.lua"

if command -v luac5.1 >/dev/null 2>&1; then
    LUAC=luac5.1
elif command -v luac >/dev/null 2>&1; then
    LUAC=luac
else
    fail "luac not found (install Lua 5.1 for the pinned KOReader-compatible syntax check)"
fi

find "$PLUGIN_DIR" -type f -name '*.lua' -print | LC_ALL=C sort | while IFS= read -r lua_file; do
    "$LUAC" -p "$lua_file"
    printf '%s\n' "syntax ok: ${lua_file#"$ROOT_DIR"/}"
done

if command -v git >/dev/null 2>&1 && [ -d "$ROOT_DIR/.git" ]; then
    if git -C "$ROOT_DIR" grep -nE 'Token[[:space:]]+[A-Za-z0-9._-]{24,}' -- ':!*.md' ':!LICENSE' >/dev/null 2>&1; then
        fail "possible committed token detected"
    fi
fi

printf '%s\n' "dev-check: OK"
