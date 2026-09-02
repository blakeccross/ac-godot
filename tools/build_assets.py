#!/usr/bin/env python3
"""Animal Crossing (GameCube) → Godot asset pipeline."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from asset_pipeline.config import load_config  # noqa: E402
from asset_pipeline.convert import (  # noqa: E402
    BUG_STATIC_NEEDLES,
    FISH_STATIC_NEEDLES,
    WATER_STATIC_NEEDLES,
    convert_acre_collision,
    convert_assets,
    convert_ckf_prefixes,
    convert_ckf_starting_with,
    convert_static_only,
    convert_static_prefixes,
    convert_test_static_needles,
)
from asset_pipeline.fgdata import convert_fgdata  # noqa: E402
from asset_pipeline.npc_rooms import convert_npc_rooms  # noqa: E402
from asset_pipeline.audio import convert_audio  # noqa: E402
from asset_pipeline.dialogue import convert_dialogue  # noqa: E402
from asset_pipeline.villagers import generate_villagers  # noqa: E402
from asset_pipeline.seasons import export_seasonal_textures  # noqa: E402
from asset_pipeline.extract import extract_archives, extract_disc  # noqa: E402
from asset_pipeline.inventory_ui import extract_inventory_ui  # noqa: E402
from asset_pipeline.faces import extract_faces  # noqa: E402
from asset_pipeline.message_ui import extract_message_ui  # noqa: E402
from asset_pipeline.scan import scan  # noqa: E402
from asset_pipeline.validate import validate  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=None)
    parser.add_argument(
        "--step",
        choices=["all", "extract", "scan", "convert", "validate"],
        default="all",
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="Convert every discovered asset (overrides config test_set_only)",
    )
    parser.add_argument(
        "--kind",
        choices=["all", "static", "buildings", "plants", "furniture", "collision", "fg", "inventory-ui", "message-ui", "dialogue", "villagers", "faces", "audio", "water", "fish", "bugs", "seasons"],
        default="all",
        help="all (default), static Gfx, outdoor buildings, palm/cedar/fruit/rock/stump overlays, furniture cKF, acre collision, FG templates, inventory UI chrome, dialogue banks, villager roster from decomp tables, NPC eye/mouth face frames, audiorom BGM catalog, river/ocean acre XLU, held fish GLBs, field insect GLBs, or seasonal field/tree albedo packs",
    )
    args = parser.parse_args()
    cfg = load_config(ROOT, args.config)
    if args.full:
        cfg.test_set_only = False

    failed = False

    if args.step in ("all", "extract"):
        extract_disc(cfg)
        extract_archives(cfg)
        print(f"extracted -> {cfg.work_root / 'extracted'}")
    if args.step in ("all", "scan"):
        manifest = scan(cfg)
        print(f"scanned {manifest['asset_count']} assets")
    if args.step in ("all", "convert"):
        errors: list[dict] = []
        if args.kind == "collision":
            col = convert_acre_collision(cfg)
            print(f"wrote {col['converted']} acre collision sidecars")
        elif args.kind == "fg":
            fg = convert_fgdata(cfg)
            if fg.get("error"):
                print(f"fgdata: {fg['error']}")
                failed = True
            else:
                print(
                    f"wrote FG catalog ({fg['templates']} templates, "
                    f"{fg['combis']} combis, {fg['combis_with_trees']} with trees)"
                )
            npc = convert_npc_rooms(cfg)
            if npc.get("error"):
                print(f"npc_rooms: {npc['error']}")
                failed = True
            else:
                print(
                    f"wrote NPC room layouts ({npc['villagers']} villagers, "
                    f"{npc['placements']} furniture) -> {npc.get('path', '')}"
                )
        elif args.kind == "message-ui":
            report = extract_message_ui(cfg)
            if report.get("error"):
                print(f"message-ui: {report['error']}")
                failed = True
            else:
                converted = report["converted"]
                errors = [r for r in report["results"] if r["status"] == "error"]
                print(f"wrote {converted} message UI assets (tiles + baked shapes) -> {report['output']}")
                for err in errors[:40]:
                    print(f"  ERROR {err.get('asset_id')}: {err.get('error')}")
                if errors:
                    failed = True
        elif args.kind == "faces":
            report = extract_faces(cfg)
            if report.get("error"):
                print(f"faces: {report['error']}")
                failed = True
            else:
                converted = report["converted"]
                errors = [r for r in report["results"] if r["status"] == "error"]
                print(f"wrote {converted} NPC face frames -> {report['output']}")
                for err in errors[:40]:
                    print(f"  ERROR {err.get('asset_id')}: {err.get('error')}")
                if errors:
                    failed = True
        elif args.kind == "inventory-ui":
            report = extract_inventory_ui(cfg)
            if report.get("error"):
                print(f"inventory-ui: {report['error']}")
                failed = True
            else:
                converted = report["converted"]
                errors = [r for r in report["results"] if r["status"] == "error"]
                print(f"wrote {converted} inventory UI textures -> {report['output']}")
                for err in errors[:40]:
                    print(f"  ERROR {err.get('asset_id')}: {err.get('error')}")
                if errors:
                    failed = True
        elif args.kind == "villagers":
            report = generate_villagers(cfg)
            if report.get("error"):
                print(f"villagers: {report['error']}")
                failed = True
            else:
                print(
                    f"wrote {report['written']} villagers "
                    f"({report['starters']} starters) -> data/villagers/"
                )
        elif args.kind == "dialogue":
            report = convert_dialogue(cfg)
            if report.get("error"):
                print(f"dialogue: {report['error']}")
                failed = True
            else:
                print(
                    f"wrote {report['converted']} messages -> {report['output']} "
                    f"({report['files']} files, {report['select_count']} choices, "
                    f"{report['string_count']} strings)"
                )
        elif args.kind == "audio":
            report = convert_audio(cfg)
            if report.get("error"):
                print(f"audio: {report['error']}")
                failed = True
            else:
                print(
                    f"wrote audio catalog ({report['bgm']} bgm, "
                    f"{report['seq_sliced']} seq slices, "
                    f"rendered {report['rendered']}) -> {report['output']}"
                )
        else:
            if args.kind == "static":
                cfg.test_set_only = False
                report = convert_static_only(cfg)
                label = "static assets"
            elif args.kind == "buildings":
                cfg.test_set_only = False
                report = convert_ckf_prefixes(
                    cfg,
                    [
                        "obj_s_house1",
                        "obj_s_shop1",
                        "obj_s_myhome1",
                        "obj_s_tailor",
                        "obj_s_yubinkyoku",
                        "obj_s_station1",
                        "obj_w_house1",
                        "obj_w_shop1",
                        "obj_w_myhome1",
                        "obj_w_tailor",
                        "obj_w_yubinkyoku",
                        "obj_w_station1",
                    ],
                )
                static_report = convert_static_prefixes(
                    cfg, ["obj_s_museum", "obj_w_museum", "obj_s_kouban", "obj_w_kouban", "obj_s_shrine", "obj_w_shrine"]
                )
                report["results"].extend(static_report.get("results", []))
                label = "building assets"
            elif args.kind == "furniture":
                cfg.test_set_only = False
                report = convert_ckf_starting_with(cfg, "int_", "clk_")
                label = "furniture cKF assets"
            elif args.kind == "plants":
                cfg.test_set_only = False
                report = convert_static_prefixes(
                    cfg,
                    [
                        "obj_s_tree",
                        "obj_w_tree",
                        "obj_f_tree",
                        "obj_s_stump",
                        "obj_w_stump",
                        "obj_f_stump",
                        "palm",
                        "cedar",
                        "tree5_apple",
                        "obj_s_stone",
                        "obj_w_stone",
                        "obj_s_cstump",
                        "obj_s_pstump",
                        "obj_w_cstump",
                        "obj_w_pstump",
                        "obj_hole",
                    ],
                )
                label = "plant assets"
            elif args.kind == "water":
                cfg.test_set_only = False
                report = convert_static_prefixes(cfg, WATER_STATIC_NEEDLES)
                label = "river/ocean acre assets"
            elif args.kind == "fish":
                cfg.test_set_only = False
                report = convert_static_prefixes(cfg, FISH_STATIC_NEEDLES)
                label = "fish assets"
            elif args.kind == "bugs":
                cfg.test_set_only = False
                report = convert_test_static_needles(cfg, BUG_STATIC_NEEDLES)
                label = "bug assets"
            elif args.kind == "seasons":
                season_report = export_seasonal_textures(cfg)
                if not season_report.get("ok"):
                    print(f"seasons: {season_report.get('error', 'no textures written')}")
                    failed = True
                else:
                    print(
                        f"wrote {season_report['written']} seasonal textures "
                        f"-> {season_report.get('out', '')}"
                    )
                    if season_report.get("missing"):
                        print(f"  missing: {', '.join(season_report['missing'][:20])}")
                report = None
            else:
                report = convert_assets(cfg)
                label = "test assets" if cfg.test_set_only else "assets"
            if report is not None:
                converted = sum(1 for r in report["results"] if r["status"] == "converted")
                errors = [r for r in report["results"] if r["status"] == "error"]
                print(f"converted {converted}/{len(report['results'])} {label}")
                for err in errors[:40]:
                    print(f"  ERROR {err.get('asset_id')}: {err.get('error')}")
                if len(errors) > 40:
                    print(f"  ... {len(errors) - 40} more errors")
                if errors:
                    failed = True
    if args.step in ("all", "validate"):
        summary = validate(cfg)
        print(f"validate {summary['passed']}/{summary['count']} ok={summary['ok']}")
        if not summary.get("ok"):
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
