@AGENTS.md

## Cloud sessions: set up assets before working

A fresh cloud container has no disc, no generated assets and no Godot. The game cannot load field acres without the pipeline's `bake` output, so do this once per session before touching gameplay, tests or captures. Skip it only for docs-only or pure Python pipeline work (`tools/test.sh pipeline` needs no disc).

1. **Install tools** (not in the base image):
   - Godot 4.6 Linux x86_64 from the official GitHub releases, unzipped to `/opt/godot/godot`; `export GODOT_BIN=/opt/godot/godot`.
   - `pip3 install -r tools/requirements.txt` (Pillow, xxhash, texture2ddecoder).
   - `apt-get install -y ffmpeg` (optional; BGM falls back to WAV without it).
   - `dtk` downloads itself to `tools/.cache/dtk` on first run.
2. **Fetch the disc image** (the owner's own dump, shared privately on Google Drive). The link lives in the `AC_ISO_URL` environment secret, never in the repo: `pip3 install gdown && mkdir -p /tmp/ac && gdown --fuzzy "$AC_ISO_URL" -O /tmp/ac/GAFE01.iso`. Never place the image inside the repo or commit it.
3. **Clone the decomp** outside the repo: `git clone --depth 1 https://github.com/ACreTeam/ac-decomp /tmp/ac/ac-decomp`. FG templates, NPC rooms, villagers and audio read its headers.
4. **Write `tools/config.local.json`** (gitignored):
   ```json
   {
     "game_files": "/tmp/ac/GAFE01.iso",
     "work_root": "/tmp/ac/work",
     "decomp_root": "/tmp/ac/ac-decomp",
     "achd_enabled": false,
     "godot_bin": "/opt/godot/godot"
   }
   ```
5. **Generate assets:** `python3 tools/build_assets.py` (extract → scan → convert → bake → validate). Then `tools/capture.sh --import …` or open the project once headless so Godot imports the new files.

Check it worked: `scenes/world/acres/*.tscn` exist and `tools/test.sh` passes. Details and per-kind reruns are in [docs/asset_pipeline.md](docs/asset_pipeline.md).
