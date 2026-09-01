from __future__ import annotations

import io
import json
import math
import struct
from pathlib import Path

from PIL import Image

from .ckf import ConvertedModel
from .gfx import MeshPart, is_window_pane_dl, is_window_spill_dl, unit_normal
from .texbank import GX_CLAMP, GX_MIRROR, GX_REPEAT, wrap_to_gltf

# Field acres tile a 16×16 cell grid. Skipping REPEAT bake leaves UVs > 1, and
# GeneratedVisual forces texture_repeat off, so grass/earth clamp to the edge.
# Cap on output pixels only (a 16×128px atlas is 2048px — well under this).
MAX_WRAP_PIXELS = 8192
_EPS = 1e-5


def _field_role_for_material_name(name: str, water_kind: str = "") -> str:
    """Map a glTF material / texture name to a seasons-pack role stem."""
    if water_kind:
        return ""
    from .seasons import FIELD_ROLE_NEEDLES, _role_for_name

    return _role_for_name(name, FIELD_ROLE_NEEDLES)


def _pad4(n: int) -> int:
    return (4 - (n % 4)) % 4


def _group_parts(parts: list[MeshPart]) -> list[dict]:
    groups: list[dict] = []
    index: dict[tuple, int] = {}
    for part in parts:
        if not part.triangles:
            continue
        unlit = bool(part.unlit_fill) or is_window_pane_dl(part.name)
        spill = bool(part.ground_spill) or is_window_spill_dl(part.name)
        water_kind = part.water_kind or ""
        waterfall_layer = part.waterfall_layer or ""
        base_color = tuple(part.base_color or (1.0, 1.0, 1.0, 1.0))
        beach_prim = part.beach_prim
        if unlit:
            part.unlit_fill = True
            part.texture_png = None
            part.texture_name = ""
            part.alpha_mode = "OPAQUE"
        if spill:
            part.ground_spill = True
            part.alpha_mode = "BLEND"
        # Shirt (REPEAT) and hat (CLAMP) share segment 0x0A PNG bytes — keep them apart.
        # Window panes share the wall SETTIMG but ignore it (prim/env fill).
        # Indoor outdoor-view (white) must not merge with facade panes (black).
        # River/ocean dual tiles must not merge with a single-layer copy of water1.
        # beach_wet prim (base_color) must not merge beachA sand with beachB ocean bed.
        # wave2 (CLAMP T) must not merge with wave3 (REPEAT T) if PNG bytes ever collide.
        key = (
            part.texture_png or b"",
            part.wrap_s,
            part.wrap_t,
            unlit,
            spill,
            part.unlit_rgba,
            water_kind,
            waterfall_layer,
            part.layer1_png or b"",
            part.layer1_wrap_s,
            part.layer1_wrap_t,
            base_color,
        )
        if key not in index:
            index[key] = len(groups)
            named = part.name.split(":")[0] if (unlit or spill) else (part.texture_name or "vertex_color")
            if water_kind:
                named = f"{water_kind}_{named}"
            groups.append(
                {
                    "png": part.texture_png,
                    "name": named,
                    "wrap_s": part.wrap_s,
                    "wrap_t": part.wrap_t,
                    "unlit_fill": unlit,
                    "unlit_rgba": part.unlit_rgba,
                    "ground_spill": spill,
                    "water_kind": water_kind,
                    "waterfall_layer": waterfall_layer,
                    "layer1_png": part.layer1_png,
                    "layer1_wrap_s": part.layer1_wrap_s,
                    "layer1_wrap_t": part.layer1_wrap_t,
                    "base_color": base_color,
                    "beach_prim": beach_prim,
                    "parts": [],
                }
            )
        groups[index[key]]["parts"].append(part)
    return groups


def _bake_wrap_group(group: dict) -> None:
    """Tile/mirror the PNG for out-of-range UVs, then normalize to [0, 1] + CLAMP.

    Godot's BaseMaterial3D has one texture_repeat flag for both axes. Shirt DLs use
    wrapS=REPEAT with wrapT=CLAMP and U up to ~2.5; the importer often clamps both,
    which paints the left side of the shirt with the texture's right edge.
    """
    png = group.get("png")
    if not png:
        return
    # Scrolling water / wet-sand need live wrap; baking freezes tiles and (for beachB)
    # leaves CLAMP V UVs outside 0–1 stuck on the solid-white I4 edge row.
    if group.get("water_kind") in ("river", "ocean", "splash", "waterfall", "beach_wet"):
        return
    wrap_s = group["wrap_s"]
    wrap_t = group["wrap_t"]
    if wrap_s == GX_CLAMP and wrap_t == GX_CLAMP:
        return

    us = [v.u for part in group["parts"] for v in part.vertices]
    vs = [v.v for part in group["parts"] for v in part.vertices]
    if not us:
        return
    u_min, u_max = min(us), max(us)
    v_min, v_max = min(vs), max(vs)

    def axis_span(lo: float, hi: float, mode: int) -> tuple[int, int]:
        if mode == GX_CLAMP:
            return 0, 1
        start = math.floor(lo + 1e-6)
        end = math.ceil(hi - 1e-6)
        if end <= start:
            end = start + 1
        return start, end

    u0, u1 = axis_span(u_min, u_max, wrap_s)
    v0, v1 = axis_span(v_min, v_max, wrap_t)
    tiles_u = u1 - u0
    tiles_v = v1 - v0
    if tiles_u == 1 and tiles_v == 1 and u0 == 0 and v0 == 0:
        # UVs already in a single tile; keep sampler wrap for filtering at edges.
        return

    base = Image.open(io.BytesIO(png)).convert("RGBA")
    tw, th = base.size
    if tw * tiles_u > MAX_WRAP_PIXELS or th * tiles_v > MAX_WRAP_PIXELS:
        print(
            f"  wrap bake large for {group.get('name')}: "
            f"{tiles_u}×{tiles_v} tiles at {tw}×{th} (still baking; Godot clamps REPEAT)"
        )
    out = Image.new("RGBA", (tw * tiles_u, th * tiles_v))
    for tj in range(tiles_v):
        for ti in range(tiles_u):
            tile = base
            if wrap_s == GX_MIRROR and ((u0 + ti) & 1):
                tile = tile.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            if wrap_t == GX_MIRROR and ((v0 + tj) & 1):
                tile = tile.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
            out.paste(tile, (ti * tw, tj * th))

    buf = io.BytesIO()
    out.save(buf, format="PNG", optimize=True)
    group["png"] = buf.getvalue()
    group["wrap_s"] = GX_CLAMP
    group["wrap_t"] = GX_CLAMP

    scale_u = float(tiles_u)
    scale_v = float(tiles_v)
    for part in group["parts"]:
        part.wrap_s = GX_CLAMP
        part.wrap_t = GX_CLAMP
        part.texture_png = group["png"]
        for vertex in part.vertices:
            vertex.u = (vertex.u - u0) / scale_u
            vertex.v = (vertex.v - v0) / scale_v


def _group_alpha_mode(group: dict) -> str:
    if group.get("unlit_fill"):
        return "OPAQUE"
    if group.get("ground_spill"):
        return "BLEND"
    ## OPA I4 band; alpha carries intensity for the runtime env pulse, not coverage.
    if group.get("water_kind") == "beach_wet":
        return "OPAQUE"
    if group.get("water_kind") in ("river", "ocean", "splash", "waterfall"):
        return "BLEND"
    modes = {part.alpha_mode for part in group["parts"]}
    if "BLEND" in modes:
        return "BLEND"
    if "MASK" in modes:
        return "MASK"
    return "OPAQUE"


def _material(
    name: str,
    texture_index: int | None,
    extras: dict | None = None,
    alpha_mode: str = "OPAQUE",
    unlit_fill: bool = False,
    unlit_rgba: tuple[float, float, float, float] = (0.0, 0.0, 0.0, 1.0),
    ground_spill: bool = False,
    water_kind: str = "",
    waterfall_layer: str = "",
    wrap_s: int = GX_REPEAT,
    wrap_t: int = GX_REPEAT,
    layer1_texture_index: int | None = None,
    layer1_wrap_s: int = GX_REPEAT,
    layer1_wrap_t: int = GX_REPEAT,
    base_color: tuple[float, float, float, float] = (1.0, 1.0, 1.0, 1.0),
    beach_prim: tuple[int, int, int, int] | None = None,
) -> dict:
    mat: dict = {
        "name": name or "vertex_color",
        # GX often draws both faces; Godot editor culls backfaces otherwise.
        "doubleSided": True,
        "alphaMode": alpha_mode,
        "pbrMetallicRoughness": {
            "baseColorFactor": list(unlit_rgba) if unlit_fill else list(base_color),
            "metallicFactor": 0,
            "roughnessFactor": 1,
        },
    }
    if alpha_mode == "MASK":
        mat["alphaCutoff"] = 0.5
    if unlit_fill:
        extras = dict(extras or {})
        extras["unlit_fill"] = True
        texture_index = None
    if ground_spill:
        extras = dict(extras or {})
        extras["ground_spill"] = True
    if water_kind:
        extras = dict(extras or {})
        extras["water_kind"] = water_kind
        ## Shore wave2: GX_CLAMP T. Runtime shader masks the curvy crash with this.
        if water_kind == "ocean":
            extras["wave2_clamp_t"] = bool(layer1_wrap_t == GX_CLAMP)
        if water_kind == "waterfall":
            if waterfall_layer:
                extras["waterfall_layer"] = waterfall_layer
            extras["tile0_mirror_s"] = bool(wrap_s == GX_MIRROR)
            extras["tile0_clamp_v"] = bool(wrap_t == GX_CLAMP)
            extras["tile1_mirror_s"] = bool(layer1_wrap_s == GX_MIRROR)
            extras["tile1_clamp_v"] = bool(layer1_wrap_t == GX_CLAMP)
    if beach_prim is not None:
        extras = dict(extras or {})
        extras["beach_prim"] = [int(beach_prim[0]), int(beach_prim[1]), int(beach_prim[2]), int(beach_prim[3])]
    field_role = _field_role_for_material_name(name or "", water_kind)
    if field_role:
        extras = dict(extras or {})
        extras["field_role"] = field_role
    elif water_kind == "beach_wet":
        compact = (name or "").lower().replace("_", "")
        if "beachb" not in compact and "beach2" not in compact:
            extras = dict(extras or {})
            extras["field_role"] = "beach_wet"
    if extras:
        mat["extras"] = extras
    if texture_index is not None:
        mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": texture_index}
    if layer1_texture_index is not None:
        # Godot maps occlusionTexture → StandardMaterial3D.ao_texture (layer1 for water).
        mat["occlusionTexture"] = {"index": layer1_texture_index}
    return mat


def _vec_close(a: tuple, b: tuple, eps: float = _EPS) -> bool:
    return all(abs(x - y) <= eps for x, y in zip(a, b))


def _quat_close(a: tuple, b: tuple, eps: float = _EPS) -> bool:
    return _vec_close(a, b, eps) or _vec_close(a, tuple(-x for x in b), eps)


def _series_matches(values: list, rest: tuple, *, quat: bool = False) -> bool:
    if not values:
        return True
    cmp = _quat_close if quat else _vec_close
    return all(cmp(v, rest) for v in values)


def write_glb(path: Path, parts: list[MeshPart], extras: dict | None = None) -> None:
    groups = _group_parts(parts)
    if not groups:
        raise ValueError("No triangles to write")

    bin_chunks: list[bytes] = []
    accessors: list[dict] = []
    buffer_views: list[dict] = []
    offset = 0
    images: list[dict] = []
    textures: list[dict] = []
    samplers: list[dict] = []
    materials: list[dict] = []
    primitives: list[dict] = []
    source_dls: list[str] = []

    def add_view(blob: bytes, target: int | None = None) -> int:
        nonlocal offset
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(blob)}
        if target is not None:
            view["target"] = target
        buffer_views.append(view)
        idx = len(buffer_views) - 1
        offset += len(blob)
        bin_chunks.append(blob)
        return idx

    def add_acc(view: int, ctype: int, count: int, typ: str, extra: dict | None = None) -> int:
        acc: dict = {"bufferView": view, "componentType": ctype, "count": count, "type": typ}
        if extra:
            acc.update(extra)
        accessors.append(acc)
        return len(accessors) - 1

    for group in groups:
        _bake_wrap_group(group)
        positions: list[float] = []
        normals: list[float] = []
        uvs: list[float] = []
        indices: list[int] = []
        vertex_offset = 0
        for part in group["parts"]:
            for vertex in part.vertices:
                positions.extend((vertex.x, vertex.y, vertex.z))
                normals.extend(unit_normal(vertex.nx, vertex.ny, vertex.nz))
                uvs.extend((vertex.u, vertex.v))
            for tri in part.triangles:
                indices.extend((tri[0] + vertex_offset, tri[1] + vertex_offset, tri[2] + vertex_offset))
            source_dls.append(part.name)
            vertex_offset += len(part.vertices)

        pos_bytes = struct.pack("<" + "f" * len(positions), *positions)
        nrm_bytes = struct.pack("<" + "f" * len(normals), *normals)
        uv_bytes = struct.pack("<" + "f" * len(uvs), *uvs)
        idx_bytes = struct.pack("<" + "I" * len(indices), *indices)
        nverts = len(positions) // 3
        xs, ys, zs = positions[0::3], positions[1::3], positions[2::3]
        a_pos = add_acc(
            add_view(pos_bytes, 34962),
            5126,
            nverts,
            "VEC3",
            {"min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
        )
        a_nrm = add_acc(add_view(nrm_bytes, 34962), 5126, nverts, "VEC3")
        a_uv = add_acc(add_view(uv_bytes, 34962), 5126, nverts, "VEC2")
        a_idx = add_acc(add_view(idx_bytes, 34963), 5125, len(indices), "SCALAR")

        tex_index = None
        png = group["png"]
        if png:
            padded = png + b"\x00" * _pad4(len(png))
            view = add_view(padded)
            buffer_views[view]["byteLength"] = len(png)
            images.append({"bufferView": view, "mimeType": "image/png"})
            samplers.append(
                {
                    "magFilter": 9728,
                    "minFilter": 9728,
                    "wrapS": wrap_to_gltf(group["wrap_s"]),
                    "wrapT": wrap_to_gltf(group["wrap_t"]),
                }
            )
            textures.append({"source": len(images) - 1, "sampler": len(samplers) - 1})
            tex_index = len(textures) - 1
        layer1_index = None
        layer1 = group.get("layer1_png")
        layer1_wrap_s = int(group.get("layer1_wrap_s", GX_REPEAT))
        layer1_wrap_t = int(group.get("layer1_wrap_t", GX_REPEAT))
        if layer1:
            padded = layer1 + b"\x00" * _pad4(len(layer1))
            view = add_view(padded)
            buffer_views[view]["byteLength"] = len(layer1)
            images.append({"bufferView": view, "mimeType": "image/png"})
            ## Decomp wave2: GX_REPEAT S / GX_CLAMP T. Do not force REPEAT/REPEAT.
            samplers.append(
                {
                    "magFilter": 9728,
                    "minFilter": 9728,
                    "wrapS": wrap_to_gltf(layer1_wrap_s),
                    "wrapT": wrap_to_gltf(layer1_wrap_t),
                }
            )
            textures.append({"source": len(images) - 1, "sampler": len(samplers) - 1})
            layer1_index = len(textures) - 1
        materials.append(
            _material(
                group["name"],
                tex_index,
                alpha_mode=_group_alpha_mode(group),
                unlit_fill=bool(group.get("unlit_fill")),
                unlit_rgba=tuple(group.get("unlit_rgba") or (0.0, 0.0, 0.0, 1.0)),
                ground_spill=bool(group.get("ground_spill")),
                water_kind=str(group.get("water_kind") or ""),
                waterfall_layer=str(group.get("waterfall_layer") or ""),
                wrap_s=int(group.get("wrap_s", GX_REPEAT)),
                wrap_t=int(group.get("wrap_t", GX_REPEAT)),
                layer1_texture_index=layer1_index,
                layer1_wrap_s=layer1_wrap_s,
                layer1_wrap_t=layer1_wrap_t,
                base_color=tuple(group.get("base_color") or (1.0, 1.0, 1.0, 1.0)),
                beach_prim=group.get("beach_prim"),
            )
        )
        primitives.append(
            {
                "attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv},
                "indices": a_idx,
                "mode": 4,
                "material": len(materials) - 1,
            }
        )

    bin_blob = b"".join(bin_chunks)
    bin_blob += b"\x00" * _pad4(len(bin_blob))
    gltf: dict = {
        "asset": {"version": "2.0", "generator": "ac-godot-asset-pipeline"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": path.stem}],
        "meshes": [{"name": path.stem, "primitives": primitives}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_blob)}],
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = textures
        gltf["samplers"] = samplers
    merged_extras = {"source_dls": source_dls, "textured_groups": len(groups)}
    if extras:
        merged_extras.update(extras)
    gltf["extras"] = merged_extras
    _write_glb_file(path, gltf, bin_blob)


def write_skinned_glb(path: Path, model: ConvertedModel, extras: dict | None = None) -> None:
    """Export a skinned GLB in glTF bind-pose form + clips.

    ``ConvertedModel.bind_*`` are already in export space (wait bind stands on +Y;
    otherwise ``ckf_basis`` was applied). Mesh positions are assembled bind-pose
    verts; IBMs are ``inverse(bind_world)``.
    """
    parts = [p for p in model.parts if p.joint_index >= 0 and p.triangles]
    groups = _group_parts(parts)
    if not groups:
        raise ValueError("No triangles to write")

    bind_world_g = model.bind_world
    bind_local_g = model.bind_local

    n_joints = len(model.joints)
    children: list[list[int]] = [[] for _ in range(n_joints)]
    roots: list[int] = []
    for joint in model.joints:
        if joint.parent < 0:
            roots.append(joint.index)
        else:
            children[joint.parent].append(joint.index)

    nodes: list[dict] = []
    for i, joint in enumerate(model.joints):
        local = bind_local_g[i]
        tx, ty, tz = local.translation()
        rx, ry, rz, rw = local.rotation_quat()
        node: dict = {
            "name": joint.model_name or f"joint_{i}",
            "translation": [tx, ty, tz],
            "rotation": [rx, ry, rz, rw],
        }
        if children[i]:
            node["children"] = children[i]
        nodes.append(node)
    mesh_node = len(nodes)
    nodes.append({"name": path.stem, "mesh": 0, "skin": 0})

    bin_chunks: list[bytes] = []
    accessors: list[dict] = []
    buffer_views: list[dict] = []
    offset = 0
    images: list[dict] = []
    textures: list[dict] = []
    samplers: list[dict] = []
    materials: list[dict] = []
    primitives: list[dict] = []
    source_dls: list[str] = []
    png_to_tex: dict[tuple[bytes, int, int], int] = {}

    def add_view(blob: bytes, target: int | None = None) -> int:
        nonlocal offset
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(blob)}
        if target is not None:
            view["target"] = target
        buffer_views.append(view)
        idx = len(buffer_views) - 1
        offset += len(blob)
        bin_chunks.append(blob)
        return idx

    def add_acc(view: int, ctype: int, count: int, typ: str, extra: dict | None = None) -> int:
        acc: dict = {"bufferView": view, "componentType": ctype, "count": count, "type": typ}
        if extra:
            acc.update(extra)
        accessors.append(acc)
        return len(accessors) - 1

    def tex_index_for(group: dict) -> int | None:
        png = group["png"]
        if not png:
            return None
        key = (png, group["wrap_s"], group["wrap_t"])
        cached = png_to_tex.get(key)
        if cached is not None:
            return cached
        padded = png + b"\x00" * _pad4(len(png))
        view = add_view(padded)
        buffer_views[view]["byteLength"] = len(png)
        images.append({"bufferView": view, "mimeType": "image/png"})
        samplers.append(
            {
                "magFilter": 9728,
                "minFilter": 9728,
                "wrapS": wrap_to_gltf(group["wrap_s"]),
                "wrapT": wrap_to_gltf(group["wrap_t"]),
            }
        )
        textures.append({"source": len(images) - 1, "sampler": len(samplers) - 1})
        png_to_tex[key] = len(textures) - 1
        return png_to_tex[key]

    ibm: list[float] = []
    for world in bind_world_g:
        ibm.extend(world.inverse_affine().gltf_mat4())
    a_ibm = add_acc(add_view(struct.pack("<" + "f" * len(ibm), *ibm)), 5126, n_joints, "MAT4")

    for group in groups:
        _bake_wrap_group(group)
        positions: list[float] = []
        normals: list[float] = []
        uvs: list[float] = []
        joints_attr: list[int] = []
        weights_attr: list[float] = []
        indices: list[int] = []
        vertex_offset = 0
        for part in group["parts"]:
            for vertex in part.vertices:
                ji = vertex.joint_index if vertex.joint_index >= 0 else part.joint_index
                world = bind_world_g[ji]
                gx, gy, gz = world.transform_point(vertex.x, vertex.y, vertex.z)
                nx, ny, nz = world.transform_vector(vertex.nx, vertex.ny, vertex.nz)
                positions.extend((gx, gy, gz))
                normals.extend(unit_normal(nx, ny, nz))
                uvs.extend((vertex.u, vertex.v))
                joints_attr.extend((ji, 0, 0, 0))
                weights_attr.extend((1.0, 0.0, 0.0, 0.0))
            for tri in part.triangles:
                indices.extend((tri[0] + vertex_offset, tri[1] + vertex_offset, tri[2] + vertex_offset))
            source_dls.append(part.name)
            vertex_offset += len(part.vertices)
        if not indices:
            continue
        nverts = len(positions) // 3
        xs, ys, zs = positions[0::3], positions[1::3], positions[2::3]
        a_pos = add_acc(
            add_view(struct.pack("<" + "f" * len(positions), *positions), 34962),
            5126,
            nverts,
            "VEC3",
            {"min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
        )
        a_nrm = add_acc(
            add_view(struct.pack("<" + "f" * len(normals), *normals), 34962),
            5126,
            nverts,
            "VEC3",
        )
        a_uv = add_acc(add_view(struct.pack("<" + "f" * len(uvs), *uvs), 34962), 5126, nverts, "VEC2")
        a_joints = add_acc(
            add_view(struct.pack("<" + "H" * len(joints_attr), *joints_attr), 34962),
            5123,
            nverts,
            "VEC4",
        )
        a_weights = add_acc(
            add_view(struct.pack("<" + "f" * len(weights_attr), *weights_attr), 34962),
            5126,
            nverts,
            "VEC4",
        )
        a_idx = add_acc(
            add_view(struct.pack("<" + "I" * len(indices), *indices), 34963),
            5125,
            len(indices),
            "SCALAR",
        )
        materials.append(
            _material(
                group["name"],
                tex_index_for(group),
                alpha_mode=_group_alpha_mode(group),
                unlit_fill=bool(group.get("unlit_fill")),
                unlit_rgba=tuple(group.get("unlit_rgba") or (0.0, 0.0, 0.0, 1.0)),
                ground_spill=bool(group.get("ground_spill")),
                water_kind=str(group.get("water_kind") or ""),
                base_color=tuple(group.get("base_color") or (1.0, 1.0, 1.0, 1.0)),
                beach_prim=group.get("beach_prim"),
            )
        )
        primitives.append(
            {
                "attributes": {
                    "POSITION": a_pos,
                    "NORMAL": a_nrm,
                    "TEXCOORD_0": a_uv,
                    "JOINTS_0": a_joints,
                    "WEIGHTS_0": a_weights,
                },
                "indices": a_idx,
                "mode": 4,
                "material": len(materials) - 1,
            }
        )

    if not primitives:
        raise ValueError("No triangles to write")

    animations_out: list[dict] = []
    baked_names: list[str] = []
    for anim_name, channels in model.animations.items():
        if not channels or not channels[0].times:
            continue
        times = channels[0].times
        a_time = add_acc(
            add_view(struct.pack("<" + "f" * len(times), *times)),
            5126,
            len(times),
            "SCALAR",
            {"min": [times[0]], "max": [times[-1]]},
        )
        samplers_anim: list[dict] = []
        channels_anim: list[dict] = []
        for ji, channel in enumerate(channels):
            if not channel.times:
                continue
            bind_t = bind_local_g[ji].translation()
            bind_r = bind_local_g[ji].rotation_quat()
            if not _series_matches(channel.translations, bind_t):
                flat_t: list[float] = []
                for tr in channel.translations:
                    flat_t.extend(tr)
                a_tr = add_acc(add_view(struct.pack("<" + "f" * len(flat_t), *flat_t)), 5126, len(times), "VEC3")
                s_tr = len(samplers_anim)
                samplers_anim.append({"input": a_time, "output": a_tr, "interpolation": "LINEAR"})
                channels_anim.append({"sampler": s_tr, "target": {"node": ji, "path": "translation"}})
            if not _series_matches(channel.rotations, bind_r, quat=True):
                flat_r: list[float] = []
                for rot in channel.rotations:
                    flat_r.extend(rot)
                a_rot = add_acc(add_view(struct.pack("<" + "f" * len(flat_r), *flat_r)), 5126, len(times), "VEC4")
                s_rot = len(samplers_anim)
                samplers_anim.append({"input": a_time, "output": a_rot, "interpolation": "LINEAR"})
                channels_anim.append({"sampler": s_rot, "target": {"node": ji, "path": "rotation"}})
        if channels_anim:
            animations_out.append({"name": anim_name, "samplers": samplers_anim, "channels": channels_anim})
            baked_names.append(anim_name)

    bin_blob = b"".join(bin_chunks)
    bin_blob += b"\x00" * _pad4(len(bin_blob))
    gltf: dict = {
        "asset": {"version": "2.0", "generator": "ac-godot-asset-pipeline"},
        "scene": 0,
        "scenes": [{"nodes": roots + [mesh_node]}],
        "nodes": nodes,
        "meshes": [{"name": path.stem, "primitives": primitives}],
        "skins": [{"joints": list(range(n_joints)), "inverseBindMatrices": a_ibm}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_blob)}],
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = textures
        gltf["samplers"] = samplers
    if animations_out:
        gltf["animations"] = animations_out
    merged = {
        "source_dls": source_dls,
        "joint_count": n_joints,
        "baked_animations": baked_names,
        "bind": "ckf_skinned_basis",
    }
    if extras:
        merged.update(extras)
    gltf["extras"] = merged
    _write_glb_file(path, gltf, bin_blob)


def _write_glb_file(path: Path, gltf: dict, bin_blob: bytes) -> None:
    json_blob = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_blob += b" " * _pad4(len(json_blob))
    packed = b""
    packed += struct.pack("<I", len(json_blob)) + b"JSON" + json_blob
    packed += struct.pack("<I", len(bin_blob)) + b"BIN\x00" + bin_blob
    header = b"glTF" + struct.pack("<II", 2, 12 + len(packed))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + packed)
