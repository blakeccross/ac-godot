#!/usr/bin/env python3
"""Animal Crossing (GameCube) → Godot asset pipeline."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from asset_pipeline.config import load_config  # noqa: E402
from asset_pipeline.convert import convert_assets  # noqa: E402
from asset_pipeline.extract import extract_archives, extract_disc  # noqa: E402
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
    args = parser.parse_args()
    cfg = load_config(ROOT, args.config)
    if args.full:
        cfg.test_set_only = False

    if args.step in ("all", "extract"):
        extract_disc(cfg)
        extract_archives(cfg)
        print(f"extracted -> {cfg.work_root / 'extracted'}")
    if args.step in ("all", "scan"):
        manifest = scan(cfg)
        print(f"scanned {manifest['asset_count']} assets")
    if args.step in ("all", "convert"):
        report = convert_assets(cfg)
        converted = sum(1 for r in report["results"] if r["status"] == "converted")
        errors = [r for r in report["results"] if r["status"] == "error"]
        label = "test assets" if cfg.test_set_only else "assets"
        print(f"converted {converted}/{len(report['results'])} {label}")
        for err in errors[:40]:
            print(f"  ERROR {err.get('asset_id')}: {err.get('error')}")
        if len(errors) > 40:
            print(f"  ... {len(errors) - 40} more errors")
    if args.step in ("all", "validate"):
        summary = validate(cfg)
        print(f"validate {summary['passed']}/{summary['count']} ok={summary['ok']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
