"""First-run setup for ``build_assets.py``: ``config.local.json``, the ACHD pack and ac-decomp.

A fresh clone needs only ``python3 tools/build_assets.py --disc <image>``: the config is
written with defaults (asking whether to use the ACHD HD texture pack, which is then
downloaded into the work root), and the decomp headers (FG templates, NPC rooms, title
demos, audio) are shallow-cloned next to the work root when no checkout is found.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

from .config import DEFAULT_WORK_ROOT, PipelineConfig, _resolve
from .fgdata import _guess_decomp

DECOMP_URL = "https://github.com/ACreTeam/ac-decomp"
## Animal Crossing HD texture pack (Dolphin Load/Textures layout, one `GAF/` folder).
## `confirm=t` skips Drive's "can't scan for viruses" page for large files.
ACHD_URL = (
    "https://drive.usercontent.google.com/download"
    "?id=1Z8-pMx20xO8q3caiqy4NOrSNVT1veDSk&export=download&confirm=t"
)
ACHD_DIR = "achd"


def local_config_path(project_root: Path) -> Path:
    return project_root / "tools" / "config.local.json"


def write_local_config(project_root: Path, disc: Path | None, hd: bool | None) -> Path:
    """Update ``config.local.json``, creating it with defaults when missing.

    ``disc`` sets ``game_files``. ``hd`` turns the ACHD pack on (downloading it) or off;
    ``None`` keeps an existing choice and asks on a new config.
    """
    path = local_config_path(project_root)
    created = not path.exists()
    if created:
        ## Godot is found at bake time (`bake.resolve_godot_bin`).
        data = {"achd_enabled": False}
    else:
        data = json.loads(path.read_text())
    if disc is not None:
        data["game_files"] = str(disc.expanduser().resolve())
    if hd is None and created:
        hd = ask_hd()
    if hd:
        pack = fetch_achd(_resolve(project_root, data.get("work_root") or str(DEFAULT_WORK_ROOT)))
        data["achd_root"] = str(pack)
        data["achd_enabled"] = True
    elif hd is not None:
        data["achd_enabled"] = False
    path.write_text(json.dumps(data, indent=2) + "\n")
    return path


def ask_hd() -> bool:
    """Ask on a terminal; scripts and CI (no TTY) get the native textures."""
    if not sys.stdin.isatty():
        return False
    answer = input("Use the ACHD HD texture pack? Downloads ~160 MB. [y/N] ")
    return answer.strip().lower() in ("y", "yes")


def fetch_achd(work_root: Path) -> Path:
    """Download and unpack the ACHD pack under ``work_root``; reuses an earlier unpack."""
    dest = work_root / ACHD_DIR
    if any(dest.glob("*/*")):
        return dest
    dest.mkdir(parents=True, exist_ok=True)
    archive = work_root / "achd.zip"
    print(f"achd: downloading {ACHD_URL}")
    with urllib.request.urlopen(ACHD_URL) as response, archive.open("wb") as out:
        total = int(response.headers.get("Content-Length") or 0)
        done = 0
        while chunk := response.read(1 << 20):
            out.write(chunk)
            done += len(chunk)
            if total:
                print(f"\r  {done >> 20}/{total >> 20} MB", end="", flush=True)
        print()
    if not zipfile.is_zipfile(archive):
        archive.unlink()
        raise SystemExit("achd: download is not a zip (link moved or Drive quota hit); rerun with --no-hd")
    ## Unpack beside `dest` and rename, so an interrupted run is not reused as complete.
    partial = work_root / f"{ACHD_DIR}.partial"
    shutil.rmtree(partial, ignore_errors=True)
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(partial)
    dest.rmdir()
    partial.rename(dest)
    archive.unlink()
    print(f"achd: unpacked -> {dest}")
    return dest


def _has_headers(path: Path | None) -> bool:
    return path is not None and (path / "include" / "m_fg_type.h").is_file()


def ensure_decomp(cfg: PipelineConfig) -> Path | None:
    """Return an ac-decomp checkout, cloning one into ``work_root`` when none is found."""
    if _has_headers(cfg.decomp_root):
        return cfg.decomp_root
    found = _guess_decomp(cfg)
    if found is not None:
        return found
    target = cfg.decomp_root or cfg.work_root / "ac-decomp"
    if target.exists() and any(target.iterdir()):
        print(f"decomp: {target} exists but has no include/m_fg_type.h; FG, title and audio will fail")
        return None
    if shutil.which("git") is None:
        print(f"decomp: git not found; clone {DECOMP_URL} and set decomp_root")
        return None
    print(f"decomp: cloning {DECOMP_URL} -> {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(["git", "clone", "--depth", "1", DECOMP_URL, str(target)], check=False)
    if result.returncode != 0 or not _has_headers(target):
        print("decomp: clone failed; FG, title and audio will fail")
        return None
    return target
