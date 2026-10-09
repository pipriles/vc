#!/bin/sh
# Runs the native test suite (unit, data and headless simulation tests), then
# builds the browser wasm and smoke-tests it in Node for both variants and
# both pages. Data tests are skipped unless data/ exists (tools/extract.py).
set -e
cd "$(dirname "$0")"
# Tests share the simulation's globals, so run them on one thread.
# The sim allocates once per run and never frees, so skip leak tracking.
# Optimised: the sim tests run ~40x faster, which outweighs the slower build.
odin test src -o:speed -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false "$@"
if [ $# -eq 0 ] && [ -d data ] && command -v node >/dev/null 2>&1; then
	./build.sh
	node tools/smoke.mjs
fi
