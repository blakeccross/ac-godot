from __future__ import annotations

import re
from pathlib import Path

# Godot 4.6 EditorSceneFormatImporter.GLTF_HANDLE_IMAGES_*
GLTF_EMBED_UNCOMPRESSED = 3

GLB_PARAMS = {
    "meshes/ensure_tangents": "false",
    "meshes/generate_lods": "false",
    "meshes/create_shadow_meshes": "false",
    "meshes/force_disable_compression": "true",
    "meshes/light_baking": "0",
    "gltf/embedded_image_handling": str(GLTF_EMBED_UNCOMPRESSED),
}

PNG_PARAMS = {
    "compress/mode": "0",
    "mipmaps/generate": "false",
    "process/fix_alpha_border": "false",
    "detect_3d/compress_to": "0",
}


def write_import_sidecar(asset: Path) -> None:
    """Write or patch a Godot .import file so pixel-art GLB/PNG stays lossless."""
    suffix = asset.suffix.lower()
    if suffix == ".glb":
        _upsert_import(asset, "scene", "PackedScene", GLB_PARAMS, extra_remap="importer_version=1\n")
    elif suffix == ".png":
        _upsert_import(asset, "texture", "CompressedTexture2D", PNG_PARAMS)


def apply_import_settings(folder: Path) -> dict[str, int]:
    """Patch every generated GLB/PNG import and drop Godot-extracted GLB sidecars."""
    counts = {"glb": 0, "png": 0, "removed_extracts": 0}
    extract_re = re.compile(r"^(.+)_(\d+)$")
    for png in list(folder.rglob("*.png")):
        match = extract_re.match(png.stem)
        if not match:
            continue
        glb = png.with_name(match.group(1) + ".glb")
        if glb.is_file():
            png.unlink(missing_ok=True)
            Path(str(png) + ".import").unlink(missing_ok=True)
            counts["removed_extracts"] += 1
    for glb in folder.rglob("*.glb"):
        write_import_sidecar(glb)
        counts["glb"] += 1
    for png in folder.rglob("*.png"):
        write_import_sidecar(png)
        counts["png"] += 1
    return counts


def _upsert_import(
    asset: Path,
    importer: str,
    remap_type: str,
    params: dict[str, str],
    extra_remap: str = "",
) -> None:
    import_path = Path(str(asset) + ".import")
    res_path = _res_path(asset)
    if import_path.is_file():
        text = import_path.read_text()
        for key, value in params.items():
            pattern = re.compile(rf"^{re.escape(key)}=.*$", re.M)
            replacement = f"{key}={value}"
            if pattern.search(text):
                text = pattern.sub(replacement, text)
            else:
                if "[params]" in text:
                    text = text.replace("[params]\n", f"[params]\n{replacement}\n", 1)
                else:
                    text += f"\n[params]\n{replacement}\n"
        import_path.write_text(text)
        return
    lines = [
        "[remap]",
        "",
        f'importer="{importer}"',
        extra_remap.rstrip("\n"),
        f'type="{remap_type}"',
        "",
        "[deps]",
        "",
        f'source_file="{res_path}"',
        "",
        "[params]",
        "",
    ]
    lines = [line for line in lines if line is not None]
    for key, value in params.items():
        lines.append(f"{key}={value}")
    lines.append("")
    import_path.write_text("\n".join(line for line in lines if line != "") + "\n")


def _res_path(asset: Path) -> str:
    text = asset.as_posix()
    marker = "/assets/"
    idx = text.rfind(marker)
    if idx >= 0:
        return "res://" + text[idx + 1 :]
    return "res://" + asset.name
