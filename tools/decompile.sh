#!/bin/sh
# Decompiles an original binary with Ghidra headless, applying re/symbols.txt.
# Usage: tools/decompile.sh <binary> <out.c>
set -e
cd "$(dirname "$0")/.."
bin=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
out=$(mkdir -p "$(dirname "$2")" && cd "$(dirname "$2")" && pwd)/$(basename "$2")

GHIDRA=${GHIDRA:-$(brew --prefix ghidra 2>/dev/null)/libexec}
[ -d /opt/homebrew/opt/openjdk@21 ] && export JAVA_HOME=/opt/homebrew/opt/openjdk@21
proj=$(mktemp -d)
"$GHIDRA/support/analyzeHeadless" "$proj" vc -import "$bin" -scriptPath tools \
	-postScript ApplySymbols.java "$PWD/re/symbols.txt" \
	-postScript DecompileAll.java "$out" -deleteProject 2>&1 | grep -E 'ERROR|Exception' || true
rm -rf "$proj"
echo "wrote $out ($(grep -c '^// ====' "$out") functions)"
