Asset extraction and conversion for a legally obtained GameCube disc.

```sh
pip3 install -r requirements.txt
cp config.example.json config.local.json
# edit config.local.json — game_files and work_root must be absolute paths
python3 build_assets.py
```

See [docs/asset_pipeline.md](../docs/asset_pipeline.md). Do not commit `config.local.json`, `tools/.cache/`, disc images, or `assets/generated/` contents.
