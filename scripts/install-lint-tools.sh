#!/bin/bash
# Downloads the lint tools into .tools/ (gitignored): selene, luau-lsp with the Roblox type
# definitions, and Rojo (for the sourcemap luau-lsp needs to follow requires).
# Safe to run again: anything already at the pinned version is left alone.
set -euo pipefail

SELENE_VERSION="0.30.0"
LUAU_LSP_VERSION="1.70.1"
ROJO_VERSION="7.6.1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"
BIN="$TOOLS/bin"
mkdir -p "$BIN"

fetch() { # url, destination
	curl -sSfL --retry 4 --retry-delay 2 -o "$2" "$1"
}
install_zip() { # name, version, url
	local name="$1" version="$2" url="$3"
	if [ -x "$BIN/$name" ] && [ "$(cat "$TOOLS/$name.version" 2>/dev/null)" = "$version" ]; then return; fi
	echo "Installing $name $version"
	local tmp
	tmp="$(mktemp -d)"
	fetch "$url" "$tmp/$name.zip"
	unzip -o -q "$tmp/$name.zip" -d "$tmp/out"
	install -m 755 "$tmp/out/$name" "$BIN/$name"
	echo "$version" > "$TOOLS/$name.version"
	rm -rf "$tmp"
}

install_zip selene "$SELENE_VERSION" \
	"https://github.com/Kampfkarren/selene/releases/download/$SELENE_VERSION/selene-$SELENE_VERSION-linux.zip"
install_zip luau-lsp "$LUAU_LSP_VERSION" \
	"https://github.com/JohnnyMorganz/luau-lsp/releases/download/$LUAU_LSP_VERSION/luau-lsp-linux-x86_64.zip"
install_zip rojo "$ROJO_VERSION" \
	"https://github.com/rojo-rbx/rojo/releases/download/v$ROJO_VERSION/rojo-$ROJO_VERSION-linux-x86_64.zip"

if [ "$(cat "$TOOLS/globalTypes.version" 2>/dev/null)" != "$LUAU_LSP_VERSION" ]; then
	echo "Downloading Roblox type definitions"
	fetch "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$LUAU_LSP_VERSION/scripts/globalTypes.d.luau" "$TOOLS/globalTypes.d.luau"
	echo "$LUAU_LSP_VERSION" > "$TOOLS/globalTypes.version"
fi
echo "Lint tools ready in $BIN"
