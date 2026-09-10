#!/usr/bin/env python3
"""Extract the AC decomp fish (gyoei) spawn tables into a Godot data file.

Parses `ac_set_ovl_gyoei.c`: the `FISH_SPAWN(TYPE, AREA, W)` term-info arrays, the
`{count, ptr}[4]` per-half-month time-slot lists, and the `r_month` / `s_month` /
`p_month[12][2]` masters (24 half-month terms). Writes:

    data/creatures/fish_spawn_table.json
      { "terms": { "<0-23>": { "river"|"sea"|"pond": { "<slot 0-3>": [
            {"type_index": int, "spawn_area": int, "weight": int} ] } } },
        "event":  { "<slot>": [ ... ] },     # fishing tourney
        "island": { "<slot>": [ ... ] } }

`FishSpawnScheduler` reads this; the per-species `.tres` are already correct and are
not touched here.
"""

from __future__ import annotations

import json
import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "creatures" / "fish_spawn_table.json"
LOCAL = Path("/Users/blakecross/Documents/ac-decomp/src/actor/ac_set_ovl_gyoei.c")
URL = "https://raw.githubusercontent.com/ACreTeam/ac-decomp/master/src/actor/ac_set_ovl_gyoei.c"

# aGYO_TYPE_* order (== gyoei_type[] index).
FISH = [
    "CRUCIAN_CARP", "BROOK_TROUT", "CARP", "KOI", "CATFISH", "SMALL_BASS", "BASS",
    "LARGE_BASS", "BLUEGILL", "GIANT_CATFISH", "GIANT_SNAKEHEAD", "BARBEL_STEED",
    "DACE", "PALE_CHUB", "BITTERLING", "LOACH", "POND_SMELT", "SWEETFISH",
    "CHERRY_SALMON", "LARGE_CHAR", "RAINBOW_TROUT", "STRINGFISH", "SALMON",
    "GOLDFISH", "PIRANHA", "AROWANA", "EEL", "FRESHWATER_GOBY", "ANGELFISH",
    "GUPPY", "POPEYED_GOLDFISH", "COELACANTH", "CRAWFISH", "FROG", "KILLIFISH",
    "JELLYFISH", "SEA_BASS", "RED_SNAPPER", "BARRED_KNIFEJAW", "ARAPAIMA",
    "WHALE", "EMPTY_CAN", "BOOT", "OLD_TIRE", "SALMON2",
]
FISH_IDX = {name: i for i, name in enumerate(FISH)}

# aSOG_SPAWN_AREA_* order (ac_set_ovl_gyoei.h).
AREA = {"POOL": 0, "WATERFALL": 1, "RIVER_MOUTH": 2, "OFFING": 3, "SEA": 4,
        "RIVER": 5, "POND": 6}

MONTHS = ["january", "february", "march", "april", "may", "june", "july",
          "august", "september", "october", "november", "december"]


def load_source() -> str:
    if LOCAL.is_file():
        return LOCAL.read_text()
    return urllib.request.urlopen(URL).read().decode()


def parse_info_arrays(src: str) -> dict[str, list[dict]]:
    """`static aSOG_term_info_c NAME[N] = { FISH_SPAWN(T, A, W), ... };`

    The size is sometimes explicit (`[20]`) and sometimes left to the initializer
    (`[]`) — the sea and pond arrays are all the latter.
    """
    out: dict[str, list[dict]] = {}
    for m in re.finditer(
        r"static aSOG_term_info_c\s+(\w+)\s*\[\d*\]\s*=\s*\{(.*?)\};", src, re.S
    ):
        name, body = m.group(1), m.group(2)
        entries = []
        for e in re.finditer(r"FISH_SPAWN\(\s*(\w+)\s*,\s*(\w+)\s*,\s*(\d+)\s*\)", body):
            entries.append({
                "type_index": FISH_IDX[e.group(1)],
                "spawn_area": AREA[e.group(2)],
                "weight": int(e.group(3)),
            })
        out[name] = entries
    return out


def parse_term_lists(src: str, infos: dict) -> dict[str, list[list[dict]]]:
    """`static aSOG_term_list_c NAME[aSOG_TIME_NUM] = { {N, arr}, ... };` → 4 slots."""
    out: dict[str, list[list[dict]]] = {}
    for m in re.finditer(
        r"static aSOG_term_list_c\s+(\w+)\s*\[aSOG_TIME_NUM\]\s*=\s*\{(.*?)\};", src, re.S
    ):
        name, body = m.group(1), m.group(2)
        slots = re.findall(r"\{\s*\d+\s*,\s*(\w+)\s*\}", body)
        out[name] = [infos.get(s, []) for s in slots]
    return out


def parse_month_master(src: str, key: str, lists: dict) -> list[list[list[list[dict]]]]:
    """`static aSOG_term_list_c* KEY[lbRTC_MONTHS_MAX][aSOG_TERM_NUM] = { {a, b}, ... };`
    → [month][half][slot] = list of entries (NULL → [])."""
    m = re.search(
        rf"static aSOG_term_list_c\*\s+{key}\s*\[lbRTC_MONTHS_MAX\]\s*\[aSOG_TERM_NUM\]\s*=\s*\{{(.*?)\}};",
        src, re.S,
    )
    if not m:
        return []
    rows = re.findall(r"\{\s*(\w+)\s*,\s*(\w+)\s*\}", m.group(1))
    months = []
    for begin, latter in rows:
        b = lists.get(begin, [[], [], [], []]) if begin != "NULL" else [[], [], [], []]
        l = lists.get(latter, b) if latter != "NULL" else b
        months.append([b, l])
    return months


def slots_to_map(slots: list[list[dict]]) -> dict[str, list[dict]]:
    return {str(i): slots[i] if i < len(slots) else [] for i in range(4)}


def main() -> None:
    src = load_source()
    infos = parse_info_arrays(src)
    lists = parse_term_lists(src, infos)
    r = parse_month_master(src, "r_month", lists)
    s = parse_month_master(src, "s_month", lists)
    p = parse_month_master(src, "p_month", lists)

    terms: dict[str, dict] = {}
    for month in range(12):
        for half in range(2):
            term = month * 2 + half
            terms[str(term)] = {
                "river": slots_to_map(r[month][half] if r else []),
                "sea": slots_to_map(s[month][half] if s else []),
                "pond": slots_to_map(p[month][half] if p else []),
            }

    out = {
        "terms": terms,
        "event": slots_to_map(lists.get("f_event", [])),
        "island": slots_to_map(lists.get("f_island", [])),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=1) + "\n")
    n = sum(len(v) for t in terms.values() for w in t.values() for v in w.values())
    print(f"wrote {OUT.relative_to(ROOT)} — 24 terms, {n} entries")


if __name__ == "__main__":
    main()
