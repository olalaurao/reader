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

# The installable plugin should remain source-sized. Catch accidental private
# dumps, caches, binaries or giant fixtures before they can enter an artifact.
find "$PLUGIN_DIR" -type f ! -path "$PLUGIN_DIR/tests/*" -print | while IFS= read -r prod_file; do
    bytes=$(wc -c < "$prod_file" | tr -d '[:space:]')
    if [ "$bytes" -gt 1048576 ]; then
        fail "unexpected production file larger than 1 MiB: ${prod_file#"$ROOT_DIR"/}"
    fi
done

if command -v git >/dev/null 2>&1 && [ -d "$ROOT_DIR/.git" ]; then
    if git -C "$ROOT_DIR" grep -nE 'Token[[:space:]]+[A-Za-z0-9._-]{24,}' -- ':!*.md' ':!LICENSE' >/dev/null 2>&1; then
        fail "possible committed token detected"
    fi

    # Signed Reader raw URLs are ephemeral credentials. Synthetic examples are
    # allowed in tests, but production/plugin files must never contain a
    # committed signed query value.
    if git -C "$ROOT_DIR" grep -nEi 'https://[^[:space:]"]+[?&](x-amz-signature|x-amz-credential|x-amz-security-token|token|signature|sig)=' --         'readwisereader.koplugin' ':!readwisereader.koplugin/tests' >/dev/null 2>&1; then
        fail "possible committed signed/credential URL detected in production plugin files"
    fi

    # Keep sensitive payload fields out of direct logger calls. This is a
    # conservative static tripwire; runtime HTTP tests separately prove URL
    # query/fragment redaction and Authorization-header non-logging.
    if git -C "$ROOT_DIR" grep -nEi 'logger[.:](dbg|info|warn|err).*authorization|logger[.:](dbg|info|warn|err).*(access[_ -]?token|raw_source_url|html_content|payload_json)' --         'readwisereader.koplugin' ':!readwisereader.koplugin/tests' >/dev/null 2>&1; then
        fail "sensitive field referenced by production logger call"
    fi
fi

printf '%s\n' "dev-check: OK"
