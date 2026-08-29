from __future__ import annotations

import os
import platform
import stat
import tempfile
import urllib.request
from pathlib import Path

DTK_VERSION = "v1.8.3"
DTK_URLS = {
    ("Darwin", "arm64"): f"https://github.com/encounter/decomp-toolkit/releases/download/{DTK_VERSION}/dtk-macos-arm64",
    ("Darwin", "x86_64"): f"https://github.com/encounter/decomp-toolkit/releases/download/{DTK_VERSION}/dtk-macos-x86_64",
    ("Linux", "x86_64"): f"https://github.com/encounter/decomp-toolkit/releases/download/{DTK_VERSION}/dtk-linux-x86_64",
    ("Linux", "aarch64"): f"https://github.com/encounter/decomp-toolkit/releases/download/{DTK_VERSION}/dtk-linux-aarch64",
    ("Windows", "AMD64"): f"https://github.com/encounter/decomp-toolkit/releases/download/{DTK_VERSION}/dtk-windows-x86_64.exe",
}
# Release binaries are 7–9 MB. A shorter file is almost certainly a failed download.
MIN_DTK_BYTES = 1_000_000


def _binary_path(path: Path) -> Path:
    """`dtk_path` may be a file or a directory (`tools/.cache/dtk`)."""
    if path.exists() and path.is_dir():
        name = "dtk.exe" if platform.system() == "Windows" else "dtk"
        return path / name
    return path


def _looks_like_dtk(path: Path) -> bool:
    return path.is_file() and path.stat().st_size >= MIN_DTK_BYTES


def ensure_dtk(path: Path) -> Path:
    dest = _binary_path(path)
    if _looks_like_dtk(dest):
        return dest
    if dest.exists():
        dest.unlink()
    key = (platform.system(), platform.machine())
    url = DTK_URLS.get(key)
    if not url:
        raise RuntimeError(f"No dtk binary for {key}. See https://github.com/encounter/decomp-toolkit/releases")
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix="dtk-", suffix=".download", dir=str(dest.parent))
    os.close(fd)
    tmp = Path(tmp_name)
    try:
        urllib.request.urlretrieve(url, tmp)
        if tmp.stat().st_size < MIN_DTK_BYTES:
            raise RuntimeError(f"dtk download was too small ({tmp.stat().st_size} bytes) from {url}")
        tmp.replace(dest)
    finally:
        tmp.unlink(missing_ok=True)
    dest.chmod(dest.stat().st_mode | stat.S_IEXEC)
    return dest
