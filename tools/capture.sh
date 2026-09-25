#!/usr/bin/env bash
# Render capture for visual checks — see scenes/dev/capture_world.gd for all args.
#   tools/capture.sh target=visual:TREE_APPLE_FRUIT date=2001-01-15,2001-04-05
#   tools/capture.sh target=node:Buildings/station cam=-6,5,9
# Prints only `CAPTURE <path>` / `CAPTURE_ERROR` / script errors. Needs a display
# (not --headless): the unit suite cannot render.
set -u
cd "$(dirname "$0")/.." || exit 2
bin="${GODOT_BIN:-}"
if [ -z "$bin" ] && [ -f tools/config.local.json ]; then
	bin=$(python3 -c "import json; print(json.load(open('tools/config.local.json')).get('godot_bin') or '')" 2>/dev/null)
fi
[ -z "$bin" ] && [ -x /Applications/Godot.app/Contents/MacOS/Godot ] && bin=/Applications/Godot.app/Contents/MacOS/Godot
[ -z "$bin" ] && bin=$(command -v godot || command -v godot4)
if [ -z "$bin" ]; then
	echo "Godot not found: set GODOT_BIN or godot_bin in tools/config.local.json" >&2
	exit 2
fi
if [ "${1:-}" = "--import" ]; then
	# Refresh the import cache after regenerating assets, or captures show stale art.
	"$bin" --headless --path . --import >/dev/null 2>&1
	shift
fi
"$bin" --path . res://scenes/dev/capture_world.tscn -- "$@" 2>&1 \
	| grep -E "^CAPTURE|SCRIPT ERROR|Parse Error|^ +at: (res|GDScript)" \
	| grep -v "Remote Debugger"
