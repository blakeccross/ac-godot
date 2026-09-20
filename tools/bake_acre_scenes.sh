#!/bin/sh
# Bake every grd_* acre GLB into a scene (see tools/bake_acre_scenes.gd). Part of the asset
# pipeline: `python3 tools/build_assets.py` runs this after converting the GLBs.
#   GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot tools/bake_acre_scenes.sh [acre_id ...]
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT_BIN:-godot}"
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . res://tools/bake_acre_scenes.tscn -- textures "$@"
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . res://tools/bake_acre_scenes.tscn -- scenes "$@"
