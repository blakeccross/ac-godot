from __future__ import annotations

import json
import os
import struct
import subprocess
from pathlib import Path
from typing import Any

from .config import PipelineConfig


def _parse_glb(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError("not a GLB")
    json_len = struct.unpack_from("<I", data, 12)[0]
    return json.loads(data[20 : 20 + json_len])


def _godot_bin() -> Path | None:
    env = os.environ.get("GODOT_BIN")
    candidates = [
        Path(env) if env else None,
        Path("/Applications/Godot.app/Contents/MacOS/Godot"),
        Path("/Applications/Godot_4.app/Contents/MacOS/Godot"),
    ]
    for path in candidates:
        if path and path.exists():
            return path
    return None


def validate(cfg: PipelineConfig) -> dict[str, Any]:
    reports: list[dict[str, Any]] = []
    converted = cfg.converted
    if not converted.exists():
        return {"ok": False, "error": "converted/ missing"}

    for path in sorted(converted.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(converted).as_posix()
        item: dict[str, Any] = {
            "path": rel,
            "exists": True,
            "size": path.stat().st_size,
            "checks": {},
            "notes": [],
        }
        if path.suffix.lower() == ".glb":
            data = path.read_bytes()
            item["checks"]["glb_magic"] = data[:4] == b"glTF"
            item["checks"]["nonempty"] = len(data) > 64
            try:
                gltf = _parse_glb(path)
                prim = gltf["meshes"][0]["primitives"][0]
                pos_acc = gltf["accessors"][prim["attributes"]["POSITION"]]
                idx_acc = gltf["accessors"][prim["indices"]]
                nverts = pos_acc["count"]
                nidx = idx_acc["count"]
                bounds = {"min": pos_acc.get("min"), "max": pos_acc.get("max")}
                item["checks"]["has_mesh"] = nverts > 0 and nidx >= 3
                item["checks"]["has_material"] = bool(gltf.get("materials"))
                extra = gltf.get("extras", {})
                item["mesh"] = {
                    "vertices": nverts,
                    "triangles": nidx // 3,
                    "bounds": bounds,
                    "parts": extra.get("source_dls", []),
                    "animations": [a.get("name") for a in gltf.get("animations", [])],
                    "joints": extra.get("joint_count"),
                }
                if extra.get("source_skeleton"):
                    item["checks"]["has_skin"] = bool(gltf.get("skins"))
                    item["notes"].append("cKF skeleton applied (bind = wait frame 1 when present)")
                if gltf.get("animations"):
                    item["notes"].append(f"baked {len(gltf['animations'])} animations")
            except Exception as exc:  # noqa: BLE001
                item["checks"]["glb_parse"] = False
                item["notes"].append(str(exc))
        elif path.suffix.lower() == ".png":
            raw = path.read_bytes()
            item["checks"]["png_magic"] = raw[:8] == b"\x89PNG\r\n\x1a\n"
            if len(raw) >= 24:
                w, h = struct.unpack(">II", raw[16:24])
                item["image"] = {"width": w, "height": h}
        godot_copy = cfg.godot_generated / rel
        item["checks"]["copied_to_godot"] = godot_copy.is_file()
        item["ok"] = all(item["checks"].values())
        reports.append(item)

    godot_import = _try_godot_import(cfg)
    summary = {
        "ok": all(r["ok"] for r in reports) if reports else False,
        "count": len(reports),
        "passed": sum(1 for r in reports if r["ok"]),
        "godot_import": godot_import,
        "assets": reports,
    }
    (cfg.manifests / "validation_report.json").write_text(json.dumps(summary, indent=2) + "\n")
    return summary


def _try_godot_import(cfg: PipelineConfig) -> dict[str, Any]:
    godot = _godot_bin()
    if godot is None:
        return {"attempted": False, "reason": "Godot binary not found. Set GODOT_BIN."}
    try:
        proc = subprocess.run(
            [str(godot), "--headless", "--path", str(cfg.project_root), "--import", "--quit"],
            capture_output=True,
            text=True,
            timeout=900,
            check=False,
        )
        player = cfg.godot_generated / "characters" / "player" / "boy_1.glb"
        imported = False
        cache = cfg.project_root / ".godot" / "imported"
        if cache.is_dir() and player.exists():
            imported = any(player.name in p.name for p in cache.glob("*"))
        return {
            "attempted": True,
            "exit_code": proc.returncode,
            "imported_player_cache": imported,
            "stderr_tail": (proc.stderr or "")[-2000:],
        }
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"attempted": True, "error": str(exc)}
