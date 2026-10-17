Asset extraction and conversion for a legally obtained GameCube disc.

```sh
pip3 install -r requirements.txt
cp config.example.json config.local.json
# edit config.local.json — game_files and work_root must be absolute paths
python3 build_assets.py
```

See [docs/asset_pipeline.md](../docs/asset_pipeline.md). Do not commit `config.local.json`, `tools/.cache/`, disc images, or `assets/generated/` contents.

## Cloud containers (Claude Code on the web)

`.claude/settings.json` runs `tools/cloud_setup.sh` at session start in cloud sessions only. It installs the Python deps, Godot 4.6 (`GODOT_BIN`), dtk, an `ac-decomp` checkout and ffmpeg under `~/ac-cache`, downloads the disc from the `AC_ISO_URL` environment secret, writes `config.local.json`, and runs `build_assets.py --step all` plus the side kinds (`villagers` excluded, it rewrites tracked `.tres`). Later sessions skip finished steps; `AC_FORCE_ASSETS=1` regenerates. Without `AC_ISO_URL` it installs the tools and stops.

The container has no display, so run gdUnit under Xvfb: `xvfb-run -a tools/test.sh <suite>`.

The bake rewrites the tracked `scenes/world/acres/*.tscn` with material hashes from this ACHD-less build. The script marks them `skip-worktree` so that local diff never lands in a commit.
