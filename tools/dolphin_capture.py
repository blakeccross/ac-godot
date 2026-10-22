#!/usr/bin/env python3
"""Dump a few frames from a Dolphin savestate.

Boots the disc in tools/config.local.json and writes PNGs under
.tmp_captures/dolphin/. Uses a temporary Dolphin user folder, so the
DumpFrames switch is not saved into the real config.

The savestate is loaded with a temporary hotkey after the boot logo. F6 never
reaches Dolphin on macOS, menu clicks do not trigger the Qt action, and
--save_state at startup clears the picture and falls through to the title.

The frames are the GameCube picture. They are not lined up with a Godot
camera, so this does not pixel-diff the two. Compare a crop of the sheet
by eye.

  python3 tools/dolphin_capture.py
  python3 tools/dolphin_capture.py --slot 6 --frames 8
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / ".tmp_captures" / "dolphin"
DISC_SUFFIXES = {".rvz", ".iso", ".gcm", ".gcz", ".wia"}
DOLPHIN_CANDIDATES = (
    Path("/Applications/Dolphin.app/Contents/MacOS/Dolphin"),
    Path("/Applications/Dolphin.app/Contents/MacOS/dolphin-emu"),
)


def _dolphin_bin() -> Path:
    env = os.environ.get("DOLPHIN_BIN", "")
    if env:
        path = Path(env)
        if path.is_file():
            return path
        raise SystemExit(f"DOLPHIN_BIN is not a file: {env}")
    for candidate in DOLPHIN_CANDIDATES:
        if candidate.is_file():
            return candidate
    raise SystemExit("Dolphin not found. Set DOLPHIN_BIN.")


def _disc(explicit: str = "") -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_file():
            raise SystemExit(f"disc not found: {path}")
        return path
    config_path = ROOT / "tools" / "config.local.json"
    if not config_path.is_file():
        raise SystemExit(f"missing {config_path}")
    game_files = Path(json.loads(config_path.read_text())["game_files"])
    if game_files.is_file() and game_files.suffix.lower() in DISC_SUFFIXES:
        return game_files
    if game_files.is_dir():
        hits = sorted(
            p for p in game_files.iterdir() if p.suffix.lower() in DISC_SUFFIXES
        )
        if len(hits) == 1:
            return hits[0]
        raise SystemExit(f"expected one disc image in {game_files}, found {hits}")
    raise SystemExit(f"game_files is not a disc or a folder of one: {game_files}")


def _state(slot: int, explicit: str) -> Path:
    if explicit:
        path = Path(explicit)
        if not path.is_file():
            raise SystemExit(f"savestate not found: {path}")
        return path
    folder = Path.home() / "Library/Application Support/Dolphin/StateSaves"
    hits = sorted(folder.glob(f"*.s{slot:02d}"))
    if not hits:
        raise SystemExit(f"no savestate slot {slot} in {folder}")
    # Prefer the Animal Crossing USA id when several games share the slot.
    for hit in hits:
        if hit.name.startswith("GAFE01"):
            return hit
    return hits[0]


# obj_fallS_model is four gsSPDisplayList calls, then gsSPEndDisplayList.
# grpAT's combiner is unique in the loaded object bank, so the model can be
# found in a savestate without a fixed guest address.
_WATERFALL_GROUPS = ("at", "bt", "ct", "dt")
_WATERFALL_AT_COMBINER = bytes.fromhex("fc32142efffefe38")
_WATERFALL_GROUP_HEADS = (
    _WATERFALL_AT_COMBINER,
    bytes.fromhex("fc61a204ff18fe7f"),
    bytes.fromhex("fc32144efffef438"),
    bytes.fromhex("fc619404fffcfeb8"),
)
_END_DISPLAY_LIST = bytes.fromhex("df00000000000000")


def _read_state(path: Path) -> tuple[bytes, bytes]:
    import struct

    import lz4.block

    raw = path.read_bytes()
    string_length = struct.unpack_from("<I", raw, 28)[0]
    extended = 32 + string_length
    header_version, compression, payload_offset, uncompressed = struct.unpack_from(
        "<HHIQ", raw, extended
    )
    if header_version != 1 or compression != 1:
        raise SystemExit(f"{path.name} is not an LZ4 Dolphin savestate")
    payload = extended + 16 + payload_offset
    compressed_length = struct.unpack_from("<i", raw, payload)[0]
    blob = lz4.block.decompress(
        raw[payload + 4 : payload + 4 + compressed_length],
        uncompressed_size=uncompressed,
    )
    return raw[:payload], blob


def _write_state(header: bytes, blob: bytes, dest: Path) -> None:
    import struct

    import lz4.block

    compressed = lz4.block.compress(blob, store_size=False)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(header + struct.pack("<i", len(compressed)) + compressed)


def _mem1_base(blob: bytes) -> int:
    cursor = 0
    while True:
        base = blob.find(b"GAFE01", cursor)
        if base < 0:
            raise SystemExit("game ram was not in this savestate")
        if blob[base + 0xF8 : base + 0xFC] == bytes.fromhex("09a7ec80"):
            return base
        cursor = base + 1


def _waterfall_group_offsets(blob: bytes) -> list[int]:
    """Blob offsets of sheets AT, BT, CT, DT.

    The object bank keeps an F3DEX copy (opcode FC) and the copy emu64 runs
    (opcode CF). The picture comes from the CF copy.
    """
    for opcode in (0xCF, 0xFC):
        offsets: list[int] = []
        for head in _WATERFALL_GROUP_HEADS:
            found = blob.find(bytes([opcode]) + head[1:])
            if found < 0:
                break
            offsets.append(found)
        if len(offsets) == len(_WATERFALL_GROUP_HEADS):
            return offsets
    raise SystemExit("waterfall sheets were not in this savestate")


# Stable instructions inside banti_draw. Branches to other modules move when
# the overlay is loaded, so the fingerprint skips those words.
_BANTI_DRAW = bytes.fromhex("546004274082045c")
_BANTI_DRAW_NEXT = bytes.fromhex("2c03000141820450")
_BLR = bytes.fromhex("4e800020")


def _hide_clock(patched: bytearray) -> None:
    """Return from the clock draw immediately. The caller's link register is untouched."""
    cursor = 0
    while True:
        found = patched.find(_BANTI_DRAW, cursor)
        if found < 0:
            raise SystemExit("clock draw was not in this savestate")
        if patched[found + 12 : found + 20] == _BANTI_DRAW_NEXT:
            entry = found - 0x1C
            if patched[entry : entry + 4] != bytes.fromhex("9421ffc0"):
                raise SystemExit("clock draw prologue did not match")
            patched[entry : entry + 4] = _BLR
            return
        cursor = found + 1


def _patch_state(state: Path, layer: str, hide_clock: bool) -> Path:
    """Copy the savestate with the clock and, optionally, waterfall sheets removed.

    The original slot file is not modified.
    """
    header, blob = _read_state(state)
    patched = bytearray(blob)
    parts: list[str] = []
    if hide_clock:
        _hide_clock(patched)
        parts.append("clock")
    if layer:
        if layer != "none" and layer not in _WATERFALL_GROUPS:
            raise SystemExit(f"unknown waterfall layer {layer}")
        # End the sheet itself. Skipping the call in the wrapper is not enough:
        # a zero command is a no-op, but the picture did not change, so end the
        # display list the call would have entered.
        for index, offset in enumerate(_waterfall_group_offsets(patched)):
            if layer != "none" and _WATERFALL_GROUPS[index] == layer:
                continue
            patched[offset : offset + 8] = _END_DISPLAY_LIST
        parts.append(layer)
    dest = OUT_DIR / "states" / f"{state.stem}_{'_'.join(parts)}{state.suffix}"
    _write_state(header, bytes(patched), dest)
    return dest


def _clock_gone(path: Path) -> bool:
    """The corner clock is a cluster of yellow discs. A redrawn frame has none."""
    try:
        from PIL import Image
    except ImportError:
        return True
    image = Image.open(path).convert("RGB")
    if image.size != (608, 472):
        return False
    pixels = image.load()
    dots = 0
    for y in range(370, 460):
        for x in range(440, 600):
            red, green, blue = pixels[x, y]
            if red > 180 and green > 160 and blue < 80:
                dots += 1
    return dots < 8


def _write_user_config(user_dir: Path, slot: int) -> None:
    """Settings on disk before launch. -C overrides the same keys in memory.

    Panic handlers off: a Yes/No alert in batch mode has no window and the
    process sits until it is killed. Async ubershaders so a cold cache still
    presents frames instead of compiling in silence.
    """
    config = user_dir / "Config"
    config.mkdir(parents=True, exist_ok=True)
    (config / "Dolphin.ini").write_text(
        "\n".join(
            [
                "[Analytics]",
                "PermissionAsked = True",
                "Enabled = False",
                "[DSP]",
                "Volume = 0",
                "[Core]",
                "EnableCheats = True",
                "[General]",
                "HotkeysRequireFocus = False",
                "[Interface]",
                "UsePanicHandlers = False",
                "ConfirmStop = False",
                "[Movie]",
                "DumpFrames = True",
                "DumpFramesSilent = True",
                "",
            ]
        )
    )
    (config / "GFX.ini").write_text(
        "\n".join(
            [
                "[Settings]",
                "DumpFramesAsImages = True",
                "InternalResolution = 1",
                "AspectRatio = 2",
                "MSAA = 1",
                "SSAA = False",
                "ShaderCompilationMode = 3",
                "FrameDumpsResolutionType = 1",
                "WaitForShadersBeforeStarting = False",
                "",
            ]
        )
    )
    # The savestate refuses to load unless this matches the camera it was saved
    # with. 0 is Six Axis (Dolphin's default), 2 is Orbital.
    (config / "FreeLook.ini").write_text(
        "\n".join(
            [
                "[Camera1]",
                "ControlType = 2",
                "[General]",
                "Enabled = False",
                "",
            ]
        )
    )
    # F6 is a macOS system key. P is not, and this profile binds only this slot.
    (config / "Hotkeys.ini").write_text(
        "\n".join(
            [
                "[Hotkeys]",
                "Device = Quartz/0/Keyboard & Mouse",
                f"Load State/Load State Slot {slot} = P",
                "",
            ]
        )
    )
    (config / "Logger.ini").write_text(
        "\n".join(
            [
                "[Options]",
                "Verbosity = 3",
                "WriteToFile = True",
                "WriteToConsole = True",
                "[Logs]",
                "* = True",
                "MASTER = True",
                "BOOT = True",
                "CORE = True",
                "COMMON = True",
                "VIDEO = True",
                "FRAMEDUMP = True",
                "",
            ]
        )
    )


def _config_args() -> list[str]:
    # Native 1x, 4:3. FrameDumpsResolutionType 1 is aspect-corrected internal.
    pairs = {
        "Main.Movie.DumpFrames": "True",
        "Main.Movie.DumpFramesSilent": "True",
        "Main.General.HotkeysRequireFocus": "False",
        "Main.Interface.UsePanicHandlers": "False",
        "Main.Core.EnableCheats": "True",
        "Main.Analytics.PermissionAsked": "True",
        "Main.Analytics.Enabled": "False",
        "Main.DSP.Volume": "0",
        "FreeLook.Camera1.ControlType": "2",
        "GFX.Settings.DumpFramesAsImages": "True",
        "GFX.Settings.InternalResolution": "1",
        "GFX.Settings.AspectRatio": "2",
        "GFX.Settings.MSAA": "1",
        "GFX.Settings.SSAA": "False",
        "GFX.Settings.ShaderCompilationMode": "3",
        "GFX.Settings.WaitForShadersBeforeStarting": "False",
        "GFX.Settings.FrameDumpsResolutionType": "1",
    }
    args: list[str] = []
    for key, value in pairs.items():
        args.extend(["-C", f"{key}={value}"])
    return args


def _frame_index(path: Path) -> int:
    digits = "".join(ch for ch in path.stem if ch.isdigit())
    return int(digits) if digits else 0


def _pngs(folder: Path) -> list[Path]:
    if not folder.is_dir():
        return []
    frames = [p for p in folder.rglob("*.png") if p.stat().st_size > 1024]
    return sorted(frames, key=_frame_index)


def _osascript(pid: int, body: str) -> subprocess.CompletedProcess[str]:
    script = (
        'tell application "System Events"\n'
        f"  tell (first process whose unix id is {pid})\n"
        f"{body}\n"
        "  end tell\n"
        "end tell\n"
    )
    return subprocess.run(
        ["osascript", "-e", script],
        check=False,
        capture_output=True,
        text=True,
    )


def _load_state_file(pid: int, state: Path, slot: int) -> str:
    """Hold P at the HID keyboard, which is what Dolphin polls.

    System Events keystrokes never show up in CGEventSourceKeyState, so the
    hotkey thread ignores them. P is bound to this slot in the temporary profile.
    """
    del state, slot
    focused = _osascript(pid, "    set frontmost to true")
    if focused.returncode != 0:
        detail = (focused.stderr or focused.stdout).strip()
        raise SystemExit(f"could not focus Dolphin: {detail}")
    time.sleep(0.2)
    # kCGHIDEventTap = 0. Key code 35 is P. Posted to the HID tap so
    # CGEventSourceKeyState(kCGEventSourceStateHIDSystemState) sees it.
    poster = r'''
import ctypes, time
cg = ctypes.CDLL("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics")
cg.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
cg.CGEventCreateKeyboardEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool]
cg.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
down = cg.CGEventCreateKeyboardEvent(None, 35, True)
up = cg.CGEventCreateKeyboardEvent(None, 35, False)
if not down or not up:
    raise SystemExit("could not create the key event")
cg.CGEventPost(0, down)
time.sleep(0.25)
cg.CGEventPost(0, up)
'''
    result = subprocess.run(["python3", "-c", poster], check=False, capture_output=True, text=True)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        raise SystemExit(f"could not press the load-state key: {detail}")
    return "P"


def _log_text(user_dir: Path) -> str:
    parts: list[str] = []
    for path in (user_dir / "Logs" / "dolphin.log", OUT_DIR / "dolphin.log"):
        if path.is_file():
            parts.append(path.read_text(errors="replace"))
    return "\n".join(parts)


def _mean_rgb(path: Path) -> tuple[float, float, float]:
    from PIL import Image

    image = Image.open(path).convert("RGB")
    width, height = image.size
    red = green = blue = 0.0
    count = 0
    for y in range(0, height, 16):
        for x in range(0, width, 16):
            pixel = image.getpixel((x, y))
            red += pixel[0]
            green += pixel[1]
            blue += pixel[2]
            count += 1
    if count == 0:
        return (0.0, 0.0, 0.0)
    return (red / count, green / count, blue / count)


def _color_distance(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def _is_boot_logo(path: Path) -> bool:
    """The IPL logo is red on black. A restored gameplay frame has other color."""
    try:
        from PIL import Image
    except ImportError:
        return False
    image = Image.open(path).convert("RGB")
    width, height = image.size
    red = green = blue = 0.0
    count = 0
    for y in range(0, height, 16):
        for x in range(0, width, 16):
            pixel = image.getpixel((x, y))
            red += pixel[0]
            green += pixel[1]
            blue += pixel[2]
            count += 1
    if count == 0:
        return True
    return (green + blue) / count < 2.0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slot", type=int, default=6)
    parser.add_argument("--state", default="")
    parser.add_argument(
        "--disc",
        default="",
        help="Disc image to boot instead of game_files. Use the one the savestate was made with.",
    )
    parser.add_argument("--frames", type=int, default=8)
    parser.add_argument(
        "--skip",
        type=int,
        default=20,
        help="Frames to drop after the savestate picture appears, so the load hitch is gone.",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument(
        "--layer",
        choices=(*_WATERFALL_GROUPS, "none"),
        default="",
        help="Show one waterfall sheet (at, bt, ct, dt) by NOP-ing the other display lists.",
    )
    parser.add_argument(
        "--show-clock",
        action="store_true",
        help="Leave the corner clock on. Captures hide it otherwise.",
    )
    args = parser.parse_args()
    if args.frames < 1:
        raise SystemExit("--frames must be at least 1")

    dolphin = _dolphin_bin()
    disc = _disc(args.disc)
    state = _state(args.slot, args.state)
    if args.layer or not args.show_clock:
        state = _patch_state(state, args.layer, not args.show_clock)
        print(f"patched {state.name}", flush=True)
    user_dir = OUT_DIR / "user"
    if user_dir.exists():
        shutil.rmtree(user_dir, ignore_errors=True)
        if user_dir.exists():
            subprocess.run(["rm", "-rf", str(user_dir)], check=False)
    _write_user_config(user_dir, args.slot)
    saves = user_dir / "StateSaves"
    saves.mkdir(parents=True)
    shutil.copy(state, saves / f"GAFE01.s{args.slot:02d}")
    game_ini = Path.home() / "Library/Application Support/Dolphin/GameSettings/GAFE01.ini"
    if game_ini.is_file():
        dest = user_dir / "GameSettings"
        dest.mkdir(parents=True, exist_ok=True)
        shutil.copy(game_ini, dest / game_ini.name)
    log_path = OUT_DIR / "dolphin.log"

    # No --save_state: that load runs before the framebuffer exists and the
    # boot continues into the title. The slot is loaded with P once the
    # title is on screen and the game id matches the state file.
    command = [
        str(dolphin),
        "-u",
        str(user_dir),
        "-e",
        str(disc),
        "-v",
        "Metal",
        *_config_args(),
    ]
    print(f"state {state.name}", flush=True)
    print(f"disc {disc.name}", flush=True)

    with log_path.open("w") as log:
        proc = subprocess.Popen(
            command,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.monotonic() + args.timeout
        found: list[Path] = []
        loaded_at = 0
        log_at_load = ""
        before_rgb = (0.0, 0.0, 0.0)
        try:
            while time.monotonic() < deadline:
                dumped = _pngs(user_dir / "Dump")
                if proc.poll() is not None:
                    break
                if loaded_at == 0:
                    recent = dumped[-30:]
                    if len(recent) == 30 and all(not _is_boot_logo(frame) for frame in recent):
                        before_rgb = _mean_rgb(dumped[-1])
                        log_at_load = _log_text(user_dir)
                        label = _load_state_file(
                            proc.pid, saves / f"GAFE01.s{args.slot:02d}", args.slot
                        )
                        loaded_at = _frame_index(dumped[-1])
                        print(f"held {label} after frame {loaded_at}", flush=True)
                else:
                    fresh = _log_text(user_dir)[len(log_at_load) :]
                    if "could not be loaded" in fresh.lower():
                        raise SystemExit(f"Dolphin rejected slot {args.slot}")
                    # Decompressing the state takes a moment, so the first
                    # frames after the key are still the title. Keep the
                    # picture once it has left that frame and stayed there.
                    changed = [
                        frame
                        for frame in dumped
                        if _frame_index(frame) > loaded_at + args.skip
                        and _color_distance(before_rgb, _mean_rgb(frame)) > 50
                    ]
                    if changed:
                        arrived_at = _frame_index(changed[0])
                        ready = [
                            frame
                            for frame in dumped
                            if _frame_index(frame) > arrived_at + 45
                            and (args.show_clock or _clock_gone(frame))
                        ]
                        if (
                            len(ready) >= args.frames
                            and _color_distance(_mean_rgb(changed[0]), _mean_rgb(ready[0])) < 80
                        ):
                            found = ready
                            if fresh.strip():
                                print(fresh[-800:].strip(), flush=True)
                            break
                time.sleep(0.4)
            else:
                fresh = _log_text(user_dir)[len(log_at_load) :]
                if fresh.strip():
                    print(fresh[-2000:], file=sys.stderr)
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait(timeout=5)

    if not found:
        print(
            "Slot file was sent to Dolphin, but the picture stayed on the title sequence. "
            f"log: {log_path}",
            file=sys.stderr,
        )
        for extra in (log_path, user_dir / "Logs" / "dolphin.log"):
            if extra.is_file():
                print(f"--- {extra}", file=sys.stderr)
                print(extra.read_text(errors="replace")[-4000:], file=sys.stderr)
        return 1

    kept = found[: args.frames]
    if _is_boot_logo(kept[0]):
        print(
            "only the Nintendo boot logo was dumped. The savestate picture did not show up.",
            file=sys.stderr,
        )
        return 1
    if args.layer:
        dest = OUT_DIR / "layers"
        dest.mkdir(parents=True, exist_ok=True)
        target = dest / f"{args.layer}.png"
        target.write_bytes(kept[0].read_bytes())
        print(f"DOLPHIN_CAPTURE {target}")
    else:
        dest = OUT_DIR / "frames"
        dest.mkdir(parents=True, exist_ok=True)
        for old in dest.glob("*.png"):
            old.unlink()
        for index, src in enumerate(kept):
            target = dest / f"frame_{index:04d}.png"
            target.write_bytes(src.read_bytes())
            print(f"DOLPHIN_CAPTURE {target}")
    if len(found) < args.frames:
        print(
            f"stopped with {len(found)} frame(s), wanted {args.frames}. log: {log_path}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
