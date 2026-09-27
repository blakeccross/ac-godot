#!/usr/bin/env bash
# One-shot setup for a fresh cloud container (Claude Code on the web).
#
#   tools/cloud_setup.sh
#
# Installs what the asset pipeline needs (Python deps, Godot, dtk, an ac-decomp
# checkout), downloads the disc image and runs tools/build_assets.py plus the
# side kinds the game loads. Everything lands outside git: tools live in
# $AC_CACHE, generated files in the gitignored assets/generated/.
#
# Env:
#   AC_ISO_URL        Download link for a disc image you own (.iso/.gcm/.rvz, or a
#                     .zip holding one). Set it as an environment secret, never in
#                     the repo.
#   AC_ISO_PATH       Use a disc image already on disk instead of downloading.
#   AC_CACHE          Where tools, the ISO and the work root go (default ~/ac-cache).
#   AC_FORCE_ASSETS=1 Regenerate even if a previous run finished.
#
# Idempotent: every step skips when its output is already there. A missing ISO
# is not an error; the tools are still installed and the script says what to set.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
ROOT=$(pwd)

GODOT_VERSION=4.6-stable
CACHE=${AC_CACHE:-$HOME/ac-cache}
GODOT_DIR=$CACHE/godot
GODOT_BIN_PATH=$GODOT_DIR/Godot_v${GODOT_VERSION}_linux.x86_64
DECOMP=$CACHE/ac-decomp
WORK=$CACHE/work
STAMP=$CACHE/assets.stamp
mkdir -p "$CACHE"

log() { printf '[cloud_setup] %s\n' "$*" >&2; }

# Retry network fetches through flaky proxies: 4 tries, 2/4/8s backoff.
fetch() {
	local url=$1 out=$2 i
	for i in 1 2 3 4; do
		curl -fL --retry 2 -sS -o "$out.part" "$url" && mv "$out.part" "$out" && return 0
		[ "$i" -lt 4 ] && sleep $((2 ** i))
	done
	rm -f "$out.part"
	return 1
}

# --- Python deps -------------------------------------------------------------
log "pip install -r tools/requirements.txt"
PIP_ROOT_USER_ACTION=ignore python3 -m pip install -q -r tools/requirements.txt || { log "pip install failed"; exit 1; }

# --- Godot (headless import + acre bake + tests) ----------------------------
if [ ! -x "$GODOT_BIN_PATH" ]; then
	log "downloading Godot $GODOT_VERSION"
	mkdir -p "$GODOT_DIR"
	zip=$GODOT_DIR/godot.zip
	fetch "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/Godot_v${GODOT_VERSION}_linux.x86_64.zip" "$zip" \
		|| { log "Godot download failed"; exit 1; }
	unzip -qo "$zip" -d "$GODOT_DIR" && rm -f "$zip"
	chmod +x "$GODOT_BIN_PATH"
fi
export GODOT_BIN=$GODOT_BIN_PATH
mkdir -p "$HOME/.local/bin"
ln -sf "$GODOT_BIN_PATH" "$HOME/.local/bin/godot"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	grep -qs "GODOT_BIN=" "$CLAUDE_ENV_FILE" || echo "export GODOT_BIN=\"$GODOT_BIN_PATH\"" >>"$CLAUDE_ENV_FILE"
fi

# First import builds .godot/ (class cache) so tests run even without assets.
if [ ! -d .godot/imported ]; then
	log "godot --import (first run)"
	"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || log "godot --import reported errors"
fi

# --- ac-decomp (FG combis, villager tables, BGM map, title demos) ------------
if [ ! -d "$DECOMP/.git" ]; then
	log "cloning ac-decomp"
	git clone -q --depth 1 https://github.com/ACreTeam/ac-decomp "$DECOMP" || log "ac-decomp clone failed; decomp-backed kinds will be skipped"
fi

# --- Optional: ffmpeg for OGG BGM (WAV fallback otherwise) ------------------
if ! command -v ffmpeg >/dev/null && command -v apt-get >/dev/null; then
	log "installing ffmpeg"
	(apt-get install -y -qq ffmpeg >/dev/null 2>&1 || { apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq ffmpeg >/dev/null 2>&1; }) \
		|| log "ffmpeg unavailable; audio falls back to WAV"
fi

# --- Disc image ---------------------------------------------------------------
iso=${AC_ISO_PATH:-}
if [ -z "$iso" ]; then
	iso=$(find "$CACHE/iso" -maxdepth 1 -type f \( -iname '*.iso' -o -iname '*.gcm' -o -iname '*.rvz' -o -iname '*.ciso' -o -iname '*.gcz' \) 2>/dev/null | head -1)
fi
if [ -z "$iso" ] && [ -n "${AC_ISO_URL:-}" ]; then
	log "downloading disc image"
	mkdir -p "$CACHE/iso"
	name=$(basename "${AC_ISO_URL%%\?*}")
	case "$name" in *.iso | *.gcm | *.rvz | *.ciso | *.gcz | *.zip) ;; *) name=disc.iso ;; esac
	case "$AC_ISO_URL" in
	*drive.google.com* | *drive.usercontent.google.com*)
		# Drive answers large files with a virus-scan warning page, not the file.
		python3 -m pip install -q gdown || { log "pip install gdown failed"; exit 1; }
		python3 -m gdown -q "$AC_ISO_URL" -O "$CACHE/iso/$name" || { log "disc download failed (is drive.google.com allowed by the network policy?)"; exit 1; }
		;;
	*) fetch "$AC_ISO_URL" "$CACHE/iso/$name" || { log "disc download failed"; exit 1; } ;;
	esac
	if [[ "$name" == *.zip ]]; then
		unzip -qo "$CACHE/iso/$name" -d "$CACHE/iso" && rm -f "$CACHE/iso/$name"
	fi
	iso=$(find "$CACHE/iso" -type f \( -iname '*.iso' -o -iname '*.gcm' -o -iname '*.rvz' -o -iname '*.ciso' -o -iname '*.gcz' \) | head -1)
fi
if [ -z "$iso" ] || [ ! -f "$iso" ]; then
	log "no disc image: set AC_ISO_URL (environment secret) or AC_ISO_PATH. Tools are installed; assets not generated."
	exit 0
fi
case "$(realpath "$iso")" in "$ROOT"/*) log "disc image must live outside the repo: $iso"; exit 1 ;; esac

# --- Pipeline config ----------------------------------------------------------
if [ ! -f tools/config.local.json ]; then
	python3 - "$iso" "$WORK" "$DECOMP" "$GODOT_BIN_PATH" <<'EOF'
import json, sys
iso, work, decomp, godot = sys.argv[1:]
cfg = json.load(open("tools/config.example.json"))
cfg.update(game_files=iso, work_root=work, decomp_root=decomp, godot_bin=godot,
           achd_enabled=False, achd_root="")
json.dump(cfg, open("tools/config.local.json", "w"), indent=2)
EOF
	log "wrote tools/config.local.json"
fi

# --- Generate assets ----------------------------------------------------------
if [ -f "$STAMP" ] && [ "${AC_FORCE_ASSETS:-0}" != 1 ]; then
	log "assets already generated ($(cat "$STAMP")); AC_FORCE_ASSETS=1 to redo"
	exit 0
fi

status=0
run() {
	log "build_assets.py $*"
	python3 tools/build_assets.py "$@" || { log "build_assets.py $* reported errors"; status=1; }
}
# extract + scan + convert + bake + validate. Side kinds after, since bake/runtime
# only need the full convert; seasons must follow it so grass/snow sheets match.
run --step all
# `villagers` is left out: it rewrites the tracked data/villagers/*.tres.
for kind in fg seasons inventory-ui design-ui map-ui message-ui clock-ui title dialogue faces audio; do
	run --step convert --kind "$kind"
done
# Import what the side kinds wrote so the editor and tests see it.
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || log "godot --import reported errors"

date -u +%FT%TZ >"$STAMP"
[ "$status" = 0 ] && log "assets generated" || log "assets generated with per-asset errors (see output above)"
exit 0
