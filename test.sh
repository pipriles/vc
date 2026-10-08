#!/bin/sh
# Runs the native test suite (unit, data and headless simulation tests).
# Data tests are skipped unless data/ exists (tools/extract.py).
set -e
cd "$(dirname "$0")"
# Tests share the simulation's globals, so run them on one thread.
# The sim allocates once per run and never frees, so skip leak tracking.
odin test src -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_TRACK_MEMORY=false "$@"
