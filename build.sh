#!/bin/sh
# Builds the wasm module and assembles a servable site in build/.
# Serve with: python3 -m http.server 8080 --directory build
set -e
cd "$(dirname "$0")"

# Odin links js_wasm32 with wasm-ld; Homebrew's lld is keg-only.
if ! command -v wasm-ld >/dev/null 2>&1; then
	for d in /opt/homebrew/opt/lld*/bin /usr/local/opt/lld*/bin; do
		[ -x "$d/wasm-ld" ] && PATH="$d:$PATH" && break
	done
fi

mkdir -p build
odin build src -target:js_wasm32 -o:speed -out:build/vc.wasm
cp web/* build/
cp "$(odin root)/core/sys/wasm/js/odin.js" build/
ln -sfn ../data build/data
echo "built build/vc.wasm ($(wc -c < build/vc.wasm | tr -d ' ') bytes)"
