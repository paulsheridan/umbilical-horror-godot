#!/usr/bin/env bash
# Run every headless suite and fail on the first red check.
# Usage: tools/run_tests.sh [suite ...]
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
godot="${GODOT:-godot}"
suites=("$@")
if [ ${#suites[@]} -eq 0 ]; then
	suites=(autotest camera_loop host_ai_rules stalker_ai zombie_reach catch_face collector_ai processor_ai level_scene crawler_setpiece debug_vision psx_look)
fi

total=0
failed=0
for suite in "${suites[@]}"; do
	out="$("$godot" --headless --path "$root" "res://tests/$suite.tscn" 2>&1)"
	pass=$(printf '%s\n' "$out" | grep -cE '^(PASS:|PASS )')
	fail=$(printf '%s\n' "$out" | grep -cE '^(FAIL:|FAIL )')
	total=$((total + pass))
	failed=$((failed + fail))
	printf '%-14s %3d pass  %d fail\n' "$suite" "$pass" "$fail"
	if [ "$fail" -ne 0 ]; then
		printf '%s\n' "$out" | grep -E '^(FAIL:|FAIL )' | sed 's/^/    /'
	fi
done
printf 'TOTAL          %3d pass  %d fail\n' "$total" "$failed"
[ "$failed" -eq 0 ]
