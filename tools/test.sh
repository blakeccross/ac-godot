#!/usr/bin/env bash
# Quiet test runner: prints only failures, script/parse errors and the summary line.
#
#   tools/test.sh                        # all gdUnit suites (res://tests)
#   tools/test.sh intro_train_stage      # tests/unit/test_intro_train_stage.gd
#   tools/test.sh 'intro_train_*' tree_use  # globs (quote for zsh) over tests/unit/test_<name>.gd
#   tools/test.sh res://tests/unit/x.gd  # explicit path (file or directory)
#   tools/test.sh pipeline               # Python asset-pipeline unittests
#   tools/test.sh -v intro_train_stage   # full runner output
#
# Env: ACRE_PARITY_ALL etc. pass straight through. Exit code is the runner's.
set -u
cd "$(dirname "$0")/.." || exit 2

verbose=0
if [ "${1:-}" = "-v" ]; then
	verbose=1
	shift
fi

godot_bin() {
	if [ -n "${GODOT_BIN:-}" ]; then
		echo "$GODOT_BIN"
		return
	fi
	local cfg
	for cfg in tools/config.local.json tools/config.json; do
		if [ -f "$cfg" ]; then
			local bin
			bin=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('godot_bin') or '')" "$cfg" 2>/dev/null)
			if [ -n "$bin" ]; then
				echo "$bin"
				return
			fi
		fi
	done
	if [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
		echo /Applications/Godot.app/Contents/MacOS/Godot
		return
	fi
	command -v godot || command -v godot4 || true
}

run_pipeline() {
	local out status
	out=$(cd tools && python3 -m unittest discover -s asset_pipeline -p 'test_*.py' -t . 2>&1)
	status=$?
	if [ $verbose -eq 1 ] || [ $status -ne 0 ]; then
		# Failures/errors blocks + the tail summary.
		echo "$out" | awk '/^(FAIL|ERROR):/{p=1} /^Ran [0-9]+ tests/{p=0} p{print}' | tail -n 80
	fi
	echo "$out" | grep -E "^Ran [0-9]+ tests|^OK|^FAILED" | tr '\n' ' '
	echo
	return $status
}

adds=()
pipeline=0
if [ $# -eq 0 ]; then
	adds+=("res://tests")
fi
for arg in "$@"; do
	case "$arg" in
	pipeline)
		pipeline=1
		;;
	res://*)
		adds+=("$arg")
		;;
	*)
		name="${arg%.gd}"
		name="${name#test_}"
		matched=0
		for f in tests/unit/test_${name}.gd; do
			if [ -f "$f" ]; then
				adds+=("res://$f")
				matched=1
			fi
		done
		if [ $matched -eq 0 ]; then
			echo "no suite matches '$arg' (looked for tests/unit/test_${name}.gd)" >&2
			exit 2
		fi
		;;
	esac
done

status=0
if [ $pipeline -eq 1 ]; then
	run_pipeline || status=$?
fi
if [ ${#adds[@]} -eq 0 ]; then
	exit $status
fi

GODOT_BIN=$(godot_bin)
if [ -z "$GODOT_BIN" ]; then
	echo "Godot not found: set GODOT_BIN or godot_bin in tools/config.local.json" >&2
	exit 2
fi
export GODOT_BIN

args=()
for a in "${adds[@]}"; do
	args+=(--add "$a")
done

log=$(mktemp -t gdunit.XXXXXX)
./addons/gdUnit4/runtest.sh "${args[@]}" >"$log" 2>&1
gd_status=$?
# Strip ANSI colour codes once.
clean=$(sed 's/\x1b\[[0-9;]*m//g' "$log")
rm -f "$log"

if [ $verbose -eq 1 ]; then
	echo "$clean"
else
	# Script / parse errors (these abort suites silently otherwise).
	echo "$clean" | grep -E "SCRIPT ERROR|Parse Error|Failed to load script|at: (res|GDScript)" | grep -v "Remote Debugger" | sort -u | head -n 20
	# Each failing test + its report, capped per failure.
	echo "$clean" | awk '
		/ FAILED / || / ERRORED / { if (n) print ""; print; n = 1; c = 0; next }
		n && /^  res:\/\// { n = 0 }
		n && /^Statistics:/ { n = 0 }
		n && c < 12 && NF { print; c++ }
	'
	# Per-suite counts when more than one suite ran, then the overall line.
	suites=$(echo "$clean" | grep -c "^Statistics:")
	if [ "$suites" -gt 1 ]; then
		echo "$clean" | grep -E "^Run Test Suite|^Statistics:" | sed 's/ | PASSED.*//; s/ | FAILED.*//' | paste - - 2>/dev/null | awk -F'\t' '{print $1 "  " $2}' | sed 's/Run Test Suite: //' | grep -v " 0 failures.*0 errors\| 0 errors | 0 failures" | head -n 40
	fi
	echo "$clean" | grep -E "^Overall Summary:" | tail -n 1
fi
[ $gd_status -ne 0 ] && status=$gd_status
exit $status
