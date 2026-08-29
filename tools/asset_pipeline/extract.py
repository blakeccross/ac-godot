from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from .config import PipelineConfig
from .dtk import ensure_dtk


def _run(dtk: Path, args: list[str]) -> None:
    subprocess.check_call([str(dtk), *args])


def _inputs_id(cfg: PipelineConfig) -> str:
    src = cfg.game_files
    lines = [str(src)]
    if src.is_file():
        st = src.stat()
        lines.append(f"file:{st.st_mtime_ns}:{st.st_size}")
        return "\n".join(lines) + "\n"
    files_dir = src if src.name == "files" else src / "files"
    if files_dir.is_dir():
        for path in sorted(files_dir.iterdir()):
            if path.is_file():
                st = path.stat()
                lines.append(f"{path.name}:{st.st_mtime_ns}:{st.st_size}")
    return "\n".join(lines) + "\n"


def extract_inputs_id(cfg: PipelineConfig) -> str:
    return _inputs_id(cfg)


def _stamp_path(cfg: PipelineConfig) -> Path:
    return cfg.work_root / "extracted" / ".stamp"


def _extract_complete(cfg: PipelineConfig) -> bool:
    if not (cfg.extracted_disc / "files").is_dir():
        return False
    if not cfg.rel_path.is_file() or not cfg.map_path.is_file():
        return False
    if not cfg.extracted_archives.is_dir():
        return False
    try:
        next(cfg.extracted_archives.iterdir())
    except StopIteration:
        return False
    return True


def extract_is_current(cfg: PipelineConfig) -> bool:
    stamp = _stamp_path(cfg)
    if not stamp.is_file() or not _extract_complete(cfg):
        return False
    return stamp.read_text() == _inputs_id(cfg)


def _write_stamp(cfg: PipelineConfig) -> None:
    path = _stamp_path(cfg)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(_inputs_id(cfg))


def extract_disc(cfg: PipelineConfig) -> Path:
    """Copy the GameCube files/ tree into work_root without putting the image in the Godot repo."""
    dest = cfg.extracted_disc
    dest.mkdir(parents=True, exist_ok=True)
    if extract_is_current(cfg):
        print("extract: disc already up to date")
        return dest

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
    out = cfg.extracted_archives
    if extract_is_current(cfg):
        print("extract: archives already up to date")
        return out

    dtk = ensure_dtk(cfg.dtk_path)
    files_dir = cfg.extracted_disc / "files"
    out.mkdir(parents=True, exist_ok=True)

    rel_szs = files_dir / "foresta.rel.szs"
    rel_out = files_dir / "foresta.rel"
    if rel_szs.exists():
        if not rel_out.exists() or rel_szs.stat().st_mtime_ns > rel_out.stat().st_mtime_ns:
            _run(dtk, ["yaz0", "decompress", str(rel_szs), "-o", str(rel_out)])

    for arc in sorted(files_dir.glob("*.arc")):
        dest = out / arc.stem
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir(parents=True, exist_ok=True)
        _run(dtk, ["vfs", "cp", f"{arc}:", str(dest)])
    _write_stamp(cfg)
    return out
