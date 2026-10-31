#!/usr/bin/env python3
"""Write data/world/acre_gates.json from the decomp's acre-edge gate tables.

`m_random_field.c` (`mRF_gate_info2`, `mRF_gate_correct_info`) lists, per acre block type and
side, the one to three openings where villagers cross into the next acre. `mRF_CheckBeastRoad`
turns the two units of each opening into poor ground so no tree grows across them.

    {"sides": ["north", "west", "south", "east"],
     "gate_kinds": [[ [[x, z], [x, z]], ... per side ], ... per kind (index 0 = none) ],
     "block_gates": [ [kind north, west, south, east], ... per `mFM_BLOCK_TYPE_*` ]}

Units are acre-local (x, z). Run: python3 tools/gen_acre_gates.py [--decomp PATH]
(PATH defaults to decomp_root in tools/config.local.json).
"""

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

from asset_pipeline.config import load_config  # noqa: E402

SIDES = ["north", "west", "south", "east"]
SUFFIX = {"up": 0, "lt": 1, "dn": 2, "rt": 3}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decomp", type=Path, default=None)
    args = parser.parse_args()
    decomp = args.decomp or load_config(ROOT).decomp_root
    if decomp is None:
        print("pass --decomp PATH or set decomp_root in tools/config.local.json")
        return 1
    src = (Path(decomp) / "src/game/m_random_field.c").read_text()
    header = (Path(decomp) / "include/m_random_field.h").read_text()

    kinds = re.findall(r"mRF_GATE\w+", header[header.index("mRF_GATE_NONE") :])
    kinds = kinds[: kinds.index("mRF_GATE_TYPE_NUM")]
    arrays: dict[str, list[list[int]]] = {}
    for name, body in re.findall(r"static mRF_gate_c (gate\w+)\[\d+\] = \{(.*?)\};", src):
        gates = re.findall(r"GATE\((\d+), (\d+), (\d+), (\d+)\)", body)
        arrays[name] = [[[int(x0), int(z0)], [int(x1), int(z1)]] for z0, x0, z1, x1 in gates]

    gate_kinds: list[list[list[list[int]]]] = [[[], [], [], []]]
    for kind in kinds[1:]:
        m = re.match(r"mRF_GATE(\d)_TYPE(\d)", kind)
        stem = f"gate{m.group(1)}_type{m.group(2)}"
        gate_kinds.append([arrays[f"{stem}_{s}"] for s in SUFFIX])

    table = src[src.index("static u8 mRF_gate_info2") :]
    table = table[: table.index("};\n\nstatic int mRF_BlockTypeDirect2GateType")]
    rows = re.findall(r"\{([^{}]*)\}", table[table.index("=") :])
    block_gates = [[kinds.index(k) for k in re.findall(r"mRF_GATE\w+", row)] for row in rows]
    assert all(len(r) == 4 for r in block_gates), "each block type has four sides"

    out = ROOT / "data/world/acre_gates.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps({"sides": SIDES, "gate_kinds": gate_kinds, "block_gates": block_gates}, separators=(",", ":")) + "\n"
    )
    print(f"wrote {out} ({len(block_gates)} block types, {len(gate_kinds)} gate kinds)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
