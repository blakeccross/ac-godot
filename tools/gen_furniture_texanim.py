#!/usr/bin/env python3
"""Write data/furniture/texture_anims.json from the TVs' draw functions.

The television-like pieces (`ac_sum_tv01`, `ac_sum_tv02`, `ac_sum_fruittv01`, `ac_kon_snowtv`) bind
a different screen texture to segment 8 each frame while switched on, and one fixed texture when
off (`gSPSegment(..., G_MWO_SEGMENT_8, ...)`). The US release's `mv` counts one frame a game tick
and `dw` reads it `>> 1` against the `*_on_anime[]` table; the pipeline leaves that segment without
an image (`seg_08`), so the runtime binds these textures instead:

    {"<visual id>": {"off": "<texture>", "on": ["<texture>", ...], "ticks_per_frame": 2}}

Textures are `assets/generated/textures/rel/<name>.png`. Run: python3 tools/gen_furniture_texanim.py
[--decomp PATH] (defaults to the decomp next to the project, like the other generators).
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from asset_pipeline.config import load_config  # noqa: E402
from asset_pipeline.fgdata import _guess_decomp  # noqa: E402

OUT = ROOT / "data" / "furniture" / "texture_anims.json"

## source file, visual id (`int_<iam name>`), the table's name
PIECES = [
    ("ac_sum_tv01.c", "int_sum_tv01", "fST01_on_anime"),
    ("ac_sum_tv02.c", "int_sum_tv02", "fST02_on_anime"),
    ("ac_sum_fruittv01.c", "int_sum_fruittv01", "aSumFruittv01_on_anime"),
    ("ac_kon_snowtv.c", "int_kon_snowtv", "fKST_on_anime_table"),
]


def table(text: str, name: str) -> list[str]:
    match = re.search(re.escape(name) + r"\[\]\s*=\s*\{(.*?)\};", text, re.S)
    if match is None:
        raise SystemExit(f"table {name} not found")
    return re.findall(r"(\w+)_tex_txt", match.group(1))


def off_texture(text: str) -> str:
    """The fixed texture of the `else` branch: `gSPSegment(NEXT_POLY_OPA_DISP, G_MWO_SEGMENT_8, X)`."""
    names = re.findall(r"G_MWO_SEGMENT_8,\s*(\w+?)(?:_tex_txt)\)", text)
    return f"{names[-1]}_tex_txt" if names else ""


def slot_reels(decomp: Path) -> dict:
    """`aSumSlot_dw`: `aSumSlot_anim[aSumSlot_aime_idx[frame >> 1]]` on segment 8, the frame counting
    a tick while the reels spin (`dynamic_work_s[0]`) and wrapping at 242. Not tied to the switch:
    it advances only during the spin, so `kind` is `spin`."""
    text = (decomp / "src" / "furniture" / "ac_sum_slot.c").read_text()
    names = table(text, "aSumSlot_anim")
    match = re.search(r"aSumSlot_aime_idx\[\]\s*=\s*\{(.*?)\};", text, re.S)
    idx = [int(v) for v in re.findall(r"\d+", match.group(1))]
    return {
        "kind": "spin",
        "off": f"{names[idx[0]]}_tex_txt",
        "on": [f"{names[i]}_tex_txt" for i in idx],
        "ticks_per_frame": 2,
        "wrap_frames": 242,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decomp", type=Path, default=None)
    args = parser.parse_args()
    cfg = load_config(ROOT)
    decomp = args.decomp or cfg.decomp_root or _guess_decomp(cfg)
    if decomp is None:
        print("pass --decomp PATH or set decomp_root in tools/config.local.json")
        return 1
    out: dict[str, dict] = {}
    for filename, visual, name in PIECES:
        text = (Path(decomp) / "src" / "furniture" / filename).read_text()
        frames = [f"{n}_tex_txt" for n in table(text, name)]
        out[visual] = {"off": off_texture(text), "on": frames, "ticks_per_frame": 2}
    out["int_sum_slot"] = slot_reels(Path(decomp))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    for visual, row in out.items():
        print(f"{visual}: off {row['off']}, {len(row['on'])} frames")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
