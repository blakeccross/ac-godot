from __future__ import annotations

import os
import platform
import stat
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


def ensure_dtk(path: Path) -> Path:
    if path.exists():
        return path
    key = (platform.system(), platform.machine())
    url = DTK_URLS.get(key)
    if not url:
        raise RuntimeError(f"No dtk binary for {key}. See https://github.com/encounter/decomp-toolkit/releases")
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, path)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path
