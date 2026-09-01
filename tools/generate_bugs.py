#!/usr/bin/env python3
"""Generate BugData .tres files from AC decomp insect tables."""

from __future__ import annotations

import re
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data" / "creatures"
SPAWN_URL = (
    "https://raw.githubusercontent.com/ACreTeam/ac-decomp/master/src/actor/ac_set_ovl_insect.c"
)

# aINS_INSECT_TYPE_* order from ac_insect_h.h
SPECIES = [
    ("common_butterfly", "Common Butterfly", "Flits over open grass."),
    ("yellow_butterfly", "Yellow Butterfly", "This butterfly looks like a flying flower."),
    ("tiger_butterfly", "Tiger Butterfly", "Striped wings on a sunny day."),
    ("purple_butterfly", "Purple Butterfly", "Deep violet wings in the treetops."),
    ("robust_cicada", "Robust Cicada", "A loud summer singer."),
    ("walker_cicada", "Walker Cicada", "Cicada with a greenish hue."),
    ("evening_cicada", "Evening Cicada", "Sings when the sun goes down."),
    ("brown_cicada", "Brown Cicada", "The most common cicada."),
    ("bee", "Bee", "Don't disturb the hive."),
    ("common_dragonfly", "Common Dragonfly", "Skims over ponds and fields."),
    ("red_dragonfly", "Red Dragonfly", "Crimson dart in the autumn air."),
    ("darner_dragonfly", "Darner Dragonfly", "Large and quick over the water."),
    ("banded_dragonfly", "Banded Dragonfly", "Bold stripes in flight."),
    ("long_locust", "Long Locust", "Leaps from the undergrowth."),
    ("migratory_locust", "Migratory Locust", "Travels in hopping swarms."),
    ("cricket", "Cricket", "Chirps from the bushes."),
    ("grasshopper", "Grasshopper", "Springs away when approached."),
    ("bell_cricket", "Bell Cricket", "A tinkling autumn song."),
    ("pine_cricket", "Pine Cricket", "Hides among fallen needles."),
    ("drone_beetle", "Drone Beetle", "Buzzes around tree trunks."),
    ("dynastid_beetle", "Dynastid Beetle", "A horned forest heavyweight."),
    ("flat_stag_beetle", "Flat Stag Beetle", "Broad antlers on bark."),
    ("jewel_beetle", "Jewel Beetle", "Iridescent green shell."),
    ("longhorn_beetle", "Longhorn Beetle", "Antennae longer than its body."),
    ("ladybug", "Ladybug", "Red shell with black spots."),
    ("spotted_ladybug", "Spotted Ladybug", "More spots than its cousin."),
    ("mantis", "Mantis", "Praying posture on a petal."),
    ("firefly", "Firefly", "Blinks above the water at dusk."),
    ("cockroach", "Cockroach", "Scuttles in the dark."),
    ("saw_stag_beetle", "Saw Stag Beetle", "Jagged mandibles on oak."),
    ("mountain_beetle", "Mountain Beetle", "Small stag of the high woods."),
    ("giant_beetle", "Giant Beetle", "The king of beetles."),
    ("snail", "Snail", "Comes out in the rain."),
    ("mole_cricket", "Mole Cricket", "Burrows underfoot."),
    ("pond_skater", "Pond Skater", "Walks on the water surface."),
    ("bagworm", "Bagworm", "Hidden in a leafy case."),
    ("pill_bug", "Pill Bug", "Rolls up under rocks."),
    ("spider", "Spider", "Spins a web on trees."),
    ("ant", "Ant", "Tiny forager."),
    ("mosquito", "Mosquito", "Buzzes around your ears."),
]

PROGRAMS = [
    "BUTTERFLY",
    "BUTTERFLY",
    "BUTTERFLY",
    "BUTTERFLY",
    "CICADA",
    "CICADA",
    "CICADA",
    "CICADA",
    "CICADA",
    "DRAGONFLY",
    "DRAGONFLY",
    "DRAGONFLY",
    "DRAGONFLY",
    "LOCUST",
    "LOCUST",
    "LOCUST",
    "LOCUST",
    "LOCUST",
    "LOCUST",
    "BEETLE",
    "BEETLE",
    "BEETLE",
    "BEETLE",
    "BEETLE",
    "LADYBUG",
    "LADYBUG",
    "MANTIS",
    "FIREFLY",
    "COCKROACH",
    "BEETLE",
    "BEETLE",
    "BEETLE",
    "LADYBUG",
    "MOLE_CRICKET",
    "WATER_SKATER",
    "BAGWORM",
    "PILL_BUG",
    "PILL_BUG",
    "PILL_BUG",
    "PILL_BUG",
]

MODEL_BASES = [
    "act_m_monshiro",
    "act_m_monki",
    "act_m_kiageha",
    "act_m_ohmurasaki",
    "act_m_minmin",
    "act_m_tukutuku",
    "act_m_higurashi",
    "act_m_abura",
    "act_m_hachi",
    "act_m_shiokara",
    "act_m_akiakane",
    "act_m_ginyanma",
    "act_m_oniyanma",
    "act_m_syouryou",
    "act_m_tonosama",
    "act_m_koorogi",
    "act_m_kirigirisu",
    "act_m_suzumushi",
    "act_m_matumushi",
    "act_m_kanabun",
    "act_m_kabuto",
    "act_m_hirata",
    "act_m_tamamushi",
    "act_m_gomadara",
    "act_m_tentou",
    "act_m_nanahoshi",
    "act_m_kamakiri",
    "act_m_genji",
    "act_m_danna",
    "act_m_nokogiri",
    "act_m_miyama",
    "act_m_okuwa",
    "act_m_maimai",
    "act_m_kera",
    "act_m_amenbo",
    "act_m_mino",
    "act_m_dango",
    "act_m_kumo",
    "act_m_ari",
    "act_m_ka",
]

PRICES = [
    320,
    320,
    800,
    8000,
    1200,
    1600,
    3400,
    800,
    18000,
    520,
    320,
    800,
    18000,
    800,
    5400,
    520,
    520,
    1720,
    400,
    320,
    5400,
    8000,
    12000,
    800,
    520,
    800,
    1720,
    1000,
    20,
    8000,
    8000,
    40000,
    1000,
    800,
    520,
    1000,
    1000,
    1200,
    320,
    520,
]

HABITAT_MAP = {
    "ON_FLOWER": 0,
    "ON_TREE": 1,
    "RAINING_ON_FLOWER": 2,
    "FLYING": 3,
    "ON_GROUND": 4,
    "IN_BUSH": 5,
    "FLYING_NEAR_WATER": 6,
    "ON_WATER": 7,
    "UNDER_ROCK": 8,
    "UNDERGROUND": 9,
    "FLYING_NEAR_FLOWERS_OR_AROUND": 3,
    "ON_CANDY": 4,
    "ON_TRASH": 4,
    "NOTHING": -1,
}

SPAWN_RE = re.compile(
    r"INSECT_SPAWN\((\w+),\s*(\w+),\s*(\d+)\)"
)
MONTH_RE = re.compile(r"l_insect_m(\d+)_t(\d+)|l_insect_m_other_t")


def fetch_spawn_source() -> str:
    with urllib.request.urlopen(SPAWN_URL, timeout=30) as resp:
        return resp.read().decode("utf-8")


def parse_spawn_tables(source: str) -> dict[str, list[tuple[int, int, int, int]]]:
    """Map table name -> list of (type_idx, habitat, weight, term)."""
    tables: dict[str, list[tuple[int, int, int, int]]] = {}
    current: str | None = None
    current_term = 0
    for line in source.splitlines():
        if "l_insect_isl_" in line:
            current = None
            continue
        m = MONTH_RE.search(line)
        if m:
            if m.group(1):
                current = f"m{m.group(1)}_t{m.group(2)}"
                current_term = int(m.group(2)) - 1
            else:
                current = "other"
                current_term = -1
            tables.setdefault(current, [])
            continue
        if current is None:
            continue
        for sm in SPAWN_RE.finditer(line):
            species, area, weight = sm.group(1), sm.group(2), int(sm.group(3))
            if species == "NONE" or species == "SPIRIT":
                continue
            type_idx = _type_index(species)
            hab = HABITAT_MAP.get(area, -1)
            if hab < 0:
                continue
            term = current_term if current_term >= 0 else 0
            tables[current].append((type_idx, hab, weight, term))
    return tables


def _enum_name(decomp: str) -> str:
    return decomp.lower()


def _type_index(decomp: str) -> int:
    key = decomp.lower()
    aliases = {
        "common_butterfly": 0,
        "yellow_butterfly": 1,
        "tiger_butterfly": 2,
        "purple_butterfly": 3,
        "robust_cicada": 4,
        "walker_cicada": 5,
        "evening_cicada": 6,
        "brown_cicada": 7,
        "bee": 8,
        "common_dragonfly": 9,
        "red_dragonfly": 10,
        "darner_dragonfly": 11,
        "banded_dragonfly": 12,
        "long_locust": 13,
        "migratory_locust": 14,
        "cricket": 15,
        "grasshopper": 16,
        "bell_cricket": 17,
        "pine_cricket": 18,
        "drone_beetle": 19,
        "dynastid_beetle": 20,
        "flat_stag_beetle": 21,
        "jewel_beetle": 22,
        "longhorn_beetle": 23,
        "ladybug": 24,
        "spotted_ladybug": 25,
        "mantis": 26,
        "firefly": 27,
        "cockroach": 28,
        "saw_stag_beetle": 29,
        "mountain_beetle": 30,
        "giant_beetle": 31,
        "snail": 32,
        "mole_cricket": 33,
        "pond_skater": 34,
        "bagworm": 35,
        "pill_bug": 36,
        "spider": 37,
        "ant": 38,
        "mosquito": 39,
    }
    return aliases[key]


def aggregate(tables: dict[str, list[tuple[int, int, int, int]]]) -> dict[int, dict]:
    meta: dict[int, dict] = {
        i: {
            "months": set(),
            "terms": set(),
            "habitats": set(),
            "weight": 1,
            "needs_rain": False,
        }
        for i in range(len(SPECIES))
    }
    month_map = {
        "m12": 12,
        "m11": 11,
        "m10": 10,
        "m9": 9,
        "m8": 8,
        "m7": 7,
        "m6": 6,
        "m5": 5,
        "m4": 4,
        "m3": 3,
    }
    month_keys = sorted(month_map.keys(), key=len, reverse=True)
    for name, entries in tables.items():
        month = 1
        if name == "other":
            month = 0
        else:
            for key in month_keys:
                if name.startswith(key):
                    month = month_map[key]
                    break
        for type_idx, hab, weight, term in entries:
            m = meta[type_idx]
            if month == 0:
                m["months"].update([1, 2])
            else:
                m["months"].add(month)
            if term >= 0:
                m["terms"].add(term)
            m["habitats"].add(hab)
            m["weight"] = max(m["weight"], weight)
            if hab == 2:
                m["needs_rain"] = True
    return meta


def write_tres(idx: int, meta: dict) -> None:
    sid, name, desc = SPECIES[idx]
    path = OUT_DIR / f"{sid}.tres"
    months = sorted(meta["months"]) if meta["months"] else list(range(1, 13))
    terms = sorted(meta["terms"]) if meta["terms"] else list(range(6))
    habitats = sorted(meta["habitats"]) if meta["habitats"] else [3]
    catch_msg = 0xA2C + idx if idx < 0x20 else 0x2FA1 + idx
    model = f"res://assets/generated/creatures/bug/{MODEL_BASES[idx]}"
    flap = 1 if PROGRAMS[idx] in ("BUTTERFLY", "DRAGONFLY", "FIREFLY", "MANTIS") else 0
    content = f"""[gd_resource type="Resource" script_class="BugData" format=3]

[ext_resource type="Script" path="res://scripts/data/bug_data.gd" id="1"]

[resource]
script = ExtResource("1")
id = &"{sid}"
display_name = "{name}"
description = "{desc}"
category = 4
sell_price = {PRICES[idx]}
max_stack = 1
type_index = {idx}
months = PackedInt32Array({", ".join(str(m) for m in months)})
time_terms = PackedInt32Array({", ".join(str(t) for t in terms)})
habitats = PackedInt32Array({", ".join(str(h) for h in habitats)})
needs_rain = {"true" if meta["needs_rain"] else "false"}
rarity_weight = {meta["weight"]}
catch_msg = {catch_msg}
model_base = "{model}"
model_flap = {flap}
model_lift = 0.0
program = {[
        "BUTTERFLY",
        "LOCUST",
        "DRAGONFLY",
        "LADYBUG",
        "FIREFLY",
        "CICADA",
        "BEETLE",
        "COCKROACH",
        "WATER_SKATER",
        "BAGWORM",
        "PILL_BUG",
        "MOLE_CRICKET",
        "MANTIS",
    ].index(PROGRAMS[idx])}
"""
    path.write_text(content, encoding="utf-8")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    source = fetch_spawn_source()
    tables = parse_spawn_tables(source)
    meta = aggregate(tables)
    for idx in range(len(SPECIES)):
        write_tres(idx, meta[idx])
    print(f"Wrote {len(SPECIES)} bug .tres files to {OUT_DIR}")


if __name__ == "__main__":
    main()
