#!/bin/sh
# Runs the native test suite (unit, data and headless simulation tests), then
# builds the browser wasm and smoke-tests it in Node for both variants and
# both pages. Data tests are skipped unless data/ exists (tools/extract.py).
set -e
cd "$(dirname "$0")"

# One run at a time: parallel runs (several agents or terminals) heat the
# machine and slow each other down. A later run waits for the earlier one;
# a lock left by a killed run is taken over.
lock=build/.test.lock
mkdir -p build
until mkdir "$lock" 2>/dev/null; do
	pid=$(cat "$lock/pid" 2>/dev/null || true)
	if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
		rm -rf "$lock"
		continue
	fi
	[ -z "$waiting" ] && echo "waiting for another test run (pid ${pid:-?})" >&2 && waiting=1
	sleep 2
done
echo $$ > "$lock/pid"
trap 'rm -rf "$lock"' EXIT
trap 'exit 130' INT TERM

# Tests share the simulation's globals, so run them on one thread.
# The sim allocates once per run and never frees, so skip leak tracking.
# Optimised: the sim tests run ~40x faster, which outweighs the slower build.
odin test src -o:speed -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false "$@"
if [ $# -eq 0 ] && [ -d data ] && command -v node >/dev/null 2>&1; then
	./build.sh
	node tools/smoke.mjs
fi
