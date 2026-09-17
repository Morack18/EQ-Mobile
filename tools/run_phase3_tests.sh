#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"

cd "$ROOT_DIR"

compile_log="$(mktemp "${TMPDIR:-/tmp}/eq-mobile-phase3-compile.XXXXXX")"
test_log="$(mktemp "${TMPDIR:-/tmp}/eq-mobile-phase3-test.XXXXXX")"

cleanup() {
	rm -f "$compile_log" "$test_log"
}
trap cleanup EXIT

error_pattern='SCRIPT ERROR|Parse Error|Compile Error|Failed to load script'

echo "=== Phase 3: project compile scan ==="

"$GODOT_BIN" --headless --path . --editor --quit 2>&1 | tee "$compile_log"
compile_status=${PIPESTATUS[0]}

if (( compile_status != 0 )); then
	echo
	echo "Phase 3 gate: FAIL - Godot compile scan exited with status ${compile_status}."
	exit "$compile_status"
fi

if grep -Eq "$error_pattern" "$compile_log"; then
	echo
	echo "Phase 3 gate: FAIL - compile scan emitted a script/parse/compile/load error."
	exit 1
fi

echo
echo "=== Phase 3: deterministic simulation tests ==="

"$GODOT_BIN" --headless --path . --script res://tests/run_phase3_tests.gd 2>&1 | tee "$test_log"
test_status=${PIPESTATUS[0]}

if (( test_status != 0 )); then
	echo
	echo "Phase 3 gate: FAIL - Godot test process exited with status ${test_status}."
	exit "$test_status"
fi

if grep -Eq "$error_pattern" "$test_log"; then
	echo
	echo "Phase 3 gate: FAIL - test run emitted a script/parse/compile/load error."
	exit 1
fi

if ! grep -Fq "Phase 3 simulation architecture tests: PASS" "$test_log"; then
	echo
	echo "Phase 3 gate: FAIL - test runner did not report its expected PASS marker."
	exit 1
fi

echo
echo "Phase 3 gate: PASS - compile scan and deterministic simulation tests are clean."