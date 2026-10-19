#!/bin/bash
# Lints the game scripts: selene (Roblox standard library) and luau-lsp (Luau type checker with the
# Roblox API). Pass files or folders to check only those; with no arguments it checks all of src/.
#
# Fails on: selene errors, and luau-lsp syntax errors or unknown globals.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"
BIN="$TOOLS/bin"
cd "$ROOT"

if [ ! -x "$BIN/selene" ] || [ ! -x "$BIN/luau-lsp" ] || [ ! -x "$BIN/rojo" ] || [ ! -f "$TOOLS/globalTypes.d.luau" ]; then
	"$ROOT/scripts/install-lint-tools.sh"
fi

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then targets=(src); fi
status=0

echo "== selene"
if ! "$BIN/selene" --allow-warnings --display-style=quiet "${targets[@]}"; then status=1; fi

echo "== luau-lsp"
"$BIN/rojo" sourcemap default.project.json -o "$TOOLS/sourcemap.json" >/dev/null
report="$TOOLS/luau-lsp.txt"
"$BIN/luau-lsp" analyze --platform=roblox --formatter=plain \
	--definitions="$TOOLS/globalTypes.d.luau" --sourcemap="$TOOLS/sourcemap.json" \
	"${targets[@]}" 2>/dev/null | grep -v '^\[' > "$report" || true
grep -E 'SyntaxError|UnknownGlobal' "$report" && status=1
warnings=$(grep -c '(W0)' "$report" || true)
echo "luau-lsp: $warnings warnings (full list in .tools/luau-lsp.txt)"

if [ "$status" -eq 0 ]; then echo "Lint passed"; else echo "Lint FAILED"; fi
exit "$status"
