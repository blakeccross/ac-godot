from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from .config import PipelineConfig
from .dtk import ensure_dtk


def _run(dtk: Path, args: list[str]) -> None:
    subprocess.check_call([str(dtk), *args])


def extract_disc(cfg: PipelineConfig) -> Path:
    """Copy the GameCube files/ tree into work_root without putting the image in the Godot repo."""
    dest = cfg.extracted_disc
    dest.mkdir(parents=True, exist_ok=True)
    src = cfg.game_files
    dtk = ensure_dtk(cfg.dtk_path)

    if src.is_file():
        _run(dtk, ["disc", "extract", str(src), str(dest)])
        return dest

    files_dir = src if src.name == "files" else src / "files"
    sys_dir = src / "sys" if src.name != "files" else src.parent / "sys"
    if not files_dir.is_dir():
        raise FileNotFoundError(
            f"game_files must be a disc image or a Dolphin-extracted folder with files/: {src}"
        )
    out_files = dest / "files"
    out_sys = dest / "sys"
    if out_files.exists():
        shutil.rmtree(out_files)
    shutil.copytree(files_dir, out_files)
    if sys_dir.is_dir():
        if out_sys.exists():
            shutil.rmtree(out_sys)
        shutil.copytree(sys_dir, out_sys)
    return dest


def extract_archives(cfg: PipelineConfig) -> Path:
    dtk = ensure_dtk(cfg.dtk_path)
    files_dir = cfg.extracted_disc / "files"
    out = cfg.extracted_archives
    out.mkdir(parents=True, exist_ok=True)

    rel_szs = files_dir / "foresta.rel.szs"
    rel_out = files_dir / "foresta.rel"
    if rel_szs.exists() and not rel_out.exists():
        _run(dtk, ["yaz0", "decompress", str(rel_szs), "-o", str(rel_out)])

    for arc in sorted(files_dir.glob("*.arc")):
        dest = out / arc.stem
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True, exist_ok=True)
        _run(dtk, ["vfs", "cp", f"{arc}:", str(dest)])
    return out
