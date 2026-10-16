#!/bin/bash
# All checks of this package: check, format, L0 (roc test), L1 (roc-fuzz).
# Usage: scripts/test.sh [ROC [FUZZ_ROC]]. ROC (default: roc on PATH) runs check, fmt and the L0
# tests. FUZZ_ROC builds the fuzz targets (default: ROC). Env: RUNS (default
# 100000) for each fuzz target.
# Exit 0 only when all pass.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
ROC=${1:-roc}
FUZZ_ROC=${2:-$ROC}
RUNS=${RUNS:-100000}
cd "$HERE"
W=$HERE/.work
mkdir -p "$W/fuzz"
# No `..` in these paths: roc stops with PathOutsideWorkspace.
export XDG_CACHE_HOME=$W/xdg ROC_CACHE_DIR=$W/xdg/roc
FAIL=0
run() {
	local name=$1
	shift
	if "$@"; then echo "PASS $name"; else echo "FAIL $name"; FAIL=1; fi
}

"$ROC" version
[ "$FUZZ_ROC" = "$ROC" ] || "$FUZZ_ROC" version
run "check package/main.roc" "$ROC" check package/main.roc
for f in tests/*.roc fuzz/*.roc; do
	run "check $f" "$ROC" check "$f"
done
run "fmt" "$ROC" fmt --check package tests fuzz

for f in tests/*.roc; do
	log=$W/test-$(basename "$f" .roc).log
	if "$ROC" test "$f" --no-cache >"$log" 2>&1; then
		echo "PASS test $f ($(grep -m1 'passed' "$log"))"
	else
		echo "FAIL test $f ($(grep -E 'passed|failed|compiler errors' "$log" | tr -s ' \n' ' '), see $log)"
		FAIL=1
	fi
done

for f in fuzz/*.roc; do
	n=$(basename "$f" .roc)
	if ! "$FUZZ_ROC" build --fuzz "$f" --output="$W/fuzz/$n" >"$W/fuzz/$n.build.log" 2>&1; then
		echo "FAIL build $f (see $W/fuzz/$n.build.log)"
		FAIL=1
		continue
	fi
	rm -rf "$W/fuzz/art-$n"
	if "$W/fuzz/$n" run --runs="$RUNS" --seed=1 --time=0 \
		--dictionary=fuzz/dictionaries/toml.dict \
		--artifact-dir="$W/fuzz/art-$n" >"$W/fuzz/$n.log" 2>&1; then
		echo "PASS fuzz $n ($(grep -m1 '^Done' "$W/fuzz/$n.log"))"
	else
		echo "FAIL fuzz $n (exit $?, see $W/fuzz/$n.log and $W/fuzz/art-$n)"
		FAIL=1
	fi
done

echo
if [ $FAIL = 0 ]; then echo "ALL PASS"; else echo "SOME CHECKS FAIL"; exit 1; fi
