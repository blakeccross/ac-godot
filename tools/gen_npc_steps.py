#!/usr/bin/env python3
"""Villager footstep and animation-sound frames, from the decomp's `src/data/npc/npc_1_*.c`.

Each animation lists the keyframes (1-based, 30 fps) on which a foot lands (`lfoot_se_chk_pat`,
`rfoot_se_chk_pat`) and any other sound it makes (`other_se_chk_pat` with an SE number),
which `aNPC_anime_se_proc` fires as the animation passes them. Writes `data/npc/npc_steps.json`:
    {"npc_1_walk1": {"l": [1], "r": [9], "other": [{"se": 1084, "frames": [10]}]}, ...}
Usage: tools/gen_npc_steps.py [decomp_root]   (default from tools/config.local.json)
"""
import glob
import json
import os
import re
import sys


def decomp_root() -> str:
    if len(sys.argv) > 1:
        return sys.argv[1]
    cfg = json.load(open(os.path.join(os.path.dirname(__file__), "config.local.json")))
    return cfg.get("decomp_root") or "/Users/blakecross/Documents/ac-decomp"


def ints(body: str) -> list[int]:
    return [int(x, 0) for x in re.findall(r"-?0x[0-9A-Fa-f]+|-?\d+", body)]


def main() -> None:
    root = decomp_root()
    out: dict[str, dict] = {}
    skipped = 0
    for path in sorted(glob.glob(os.path.join(root, "src/data/npc/npc_1_*.c"))):
        text = open(path).read()
        if "se_dt_tbl" not in text:
            continue
        stem = os.path.basename(path)[:-2]
        pats = {m.group(1): ints(m.group(2)) for m in re.finditer(r"static int (\w+)\[\]\s*=\s*\{([^}]*)\}", text)}
        entry: dict = {}
        for key, name in (("l", "lfoot_se_chk_pat"), ("r", "rfoot_se_chk_pat")):
            if name in pats:
                entry[key] = pats[name]
        others = []
        for m in re.finditer(r"\{\s*\{\s*ARRAY_COUNT\((\w+)\)\s*,\s*\w+\s*\}\s*,\s*(\w+)\s*\}", text):
            if m.group(1) in ("lfoot_se_chk_pat", "rfoot_se_chk_pat"):
                continue
            try:
                se = int(m.group(2), 0)
            except ValueError:
                skipped += 1
                continue
            if m.group(1) in pats:
                others.append({"se": se, "frames": pats[m.group(1)]})
        if others:
            entry["other"] = others
        if entry:
            out[stem] = entry
    dst = os.path.join(os.path.dirname(__file__), "..", "data", "npc", "npc_steps.json")
    with open(dst, "w") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
        fh.write("\n")
    print(f"{len(out)} animations ({skipped} sounds named by macro skipped) -> {os.path.normpath(dst)}")


if __name__ == "__main__":
    main()
