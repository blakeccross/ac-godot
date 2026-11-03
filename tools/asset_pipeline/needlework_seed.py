"""Starting designs for the player and the Able Sisters' display board.

`mNW_InitMyOriginalTexture` copies the first four player designs out of ARAM resource 27
(`my_original.bin`) and `mNW_InitNeedleworkTexture` all eight shop designs out of
resource 28 (`needlework.bin`), 512-byte CI4 blobs in the GameCube tile order. Their names
are ROM strings 0x6DF+i (player) and 0x6E7+i (shop); the palettes are fixed tables in
`m_needlework.c`, so the runtime owns those. Needs `strings.json`-grade string decoding, so
it reads `string_data` the way the dialogue pass does.

Output is gitignored (Nintendo IP, not for commit).
"""

from __future__ import annotations

import base64
import json
from typing import Any

from .config import PipelineConfig
from .dialogue import decode_strings, find_pair

DESIGN_BYTES = 512  # mNW_DESIGN_TEX_SIZE
PLAYER_DEFAULTS = 4  # mNW_DEFAULT_ORIGINAL_TEX_NUM
SHOP_DESIGNS = 8  # mNW_TOTAL_DESIGN_NUM
PLAYER_NAME_STRING = 0x6DF
SHOP_NAME_STRING = 0x6E7


def _find_bin(cfg: PipelineConfig, name: str):
    for root in (cfg.extracted_archives / "forest_2nd" / "data", cfg.extracted_archives / "forest_1st" / "data"):
        path = root / name
        if path.is_file():
            return path
    return None


def extract_needlework_seed(cfg: PipelineConfig) -> dict[str, Any]:
    my_original = _find_bin(cfg, "my_original.bin")
    needlework = _find_bin(cfg, "needlework.bin")
    string_pair = find_pair(cfg, "string_data")
    if my_original is None or needlework is None:
        return {"error": "my_original.bin / needlework.bin not found. Extract the archives first.", "converted": 0}
    if string_pair is None:
        return {"error": "string_data.bin not found. Extract the archives first.", "converted": 0}
    strings = decode_strings(string_pair[0].read_bytes(), string_pair[1].read_bytes())
    mine = my_original.read_bytes()
    shop = needlework.read_bytes()

    def entry(blob: bytes, i: int, name_base: int) -> dict[str, Any]:
        chunk = blob[i * DESIGN_BYTES : (i + 1) * DESIGN_BYTES]
        return {"name": strings[name_base + i], "ci4": base64.b64encode(chunk).decode("ascii")}

    out = {
        "player": [entry(mine, i, PLAYER_NAME_STRING) for i in range(PLAYER_DEFAULTS)],
        "shop": [entry(shop, i, SHOP_NAME_STRING) for i in range(SHOP_DESIGNS)],
    }
    out_dir = cfg.godot_generated / "needlework"
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "seed_designs.json"
    path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"converted": PLAYER_DEFAULTS + SHOP_DESIGNS, "output": str(path)}
