from __future__ import annotations

import re
import struct
from dataclasses import dataclass, field

from .gfx import G_VTX, MeshPart, apply_texture_commands, parse_gfx, parse_vtx_blob
from .mapfile import MapSymbol, find_symbol, index_by_name
from .math3d import Mat4, ckf_basis, local_softcv3
from .rel import RelData
from .texbank import TextureBank, TextureState

BIT_TRANS_X = 1 << 5
BIT_ROT_X = 1 << 2
FPS = 30.0


@dataclass
class Joint:
    child_count: int
    flags: int
    translation: tuple[float, float, float]
    gfx_addr: int
    model_name: str | None
    parent: int
    index: int


@dataclass
class AnimChannel:
    times: list[float]
    translations: list[tuple[float, float, float]]
    rotations: list[tuple[float, float, float, float]]  # xyzw


@dataclass
class ConvertedModel:
    parts: list[MeshPart]
    joints: list[Joint]
    bind_local: list[Mat4]
    bind_world: list[Mat4]
    animations: dict[str, list[AnimChannel]]
    extras: dict = field(default_factory=dict)


def _s16s(blob: bytes) -> list[int]:
    return list(struct.unpack(">" + "h" * (len(blob) // 2), blob))


def _key_calc(start_idx: int, n_frames: int, data: list[int], frame: float) -> int:
    def key_at(i: int) -> tuple[int, int, int]:
        return data[i * 3], data[i * 3 + 1], data[i * 3 + 2]

    if key_at(start_idx)[0] >= frame:
        return key_at(start_idx)[1]
    last = start_idx + n_frames - 1
    if key_at(last)[0] <= frame:
        return key_at(last)[1]
    now = start_idx
    nxt = start_idx + 1
    while nxt <= last:
        nf, nv, nt = key_at(nxt)
        if nf > frame:
            cf, cv, ct = key_at(now)
            delta = nf - cf
            if delta == 0:
                return cv
            t = (frame - cf) / delta
            tension = delta * (1.0 / 30.0)
            t2 = t * t
            t3 = t2 * t
            pos = -(t3 * 2.0) + (3.0 * t2)
            h10 = t + (t3 - (t2 * 2.0))
            h11 = t3 - t2
            calc = ((1.0 - pos) * cv + pos * nv) + tension * (h10 * ct + h11 * nt)
            return int(calc + 0.5)
        now += 1
        nxt += 1
    return key_at(last)[1]


def _deg10_to_binangle(value: int) -> int:
    deg = (value * 0.1) % 360.0
    ang = int(deg * (65536.0 / 360.0))
    if ang >= 32768:
        ang -= 65536
    return ang


_ANIM_TABLES: dict[tuple[int, str], tuple[bytes, list[int], list[int], list[int], int]] = {}
_POSE_CACHE: dict[tuple, tuple[tuple[int, int, int], list[tuple[int, int, int]]]] = {}


def clear_caches() -> None:
    """Drop per-REL animation caches. Call when constructing a new RelData."""
    _ANIM_TABLES.clear()
    _POSE_CACHE.clear()


def _anim_tables(
    rel: RelData, symbols: list[MapSymbol], anim_name: str, num_joints: int
) -> tuple[bytes, list[int], list[int], list[int], int]:
    cache_key = (id(rel), anim_name)
    cached = _ANIM_TABLES.get(cache_key)
    if cached is not None:
        return cached
    header = find_symbol(symbols, anim_name)
    flag_p, data_p, key_p, fix_p, _pad, nframes = struct.unpack(">IIIIhh", rel.slice_at(header.address, 20))
    flags = rel.slice_at(flag_p, num_joints)
    try:
        key_sym = next(s for s in symbols if s.address == key_p and not s.name.startswith("."))
        data_sym = next(s for s in symbols if s.address == data_p and not s.name.startswith("."))
        fix_sym = next(s for s in symbols if s.address == fix_p and not s.name.startswith("."))
    except StopIteration:
        key_sym = next(s for s in symbols if s.address == key_p)
        data_sym = next(s for s in symbols if s.address == data_p)
        fix_sym = next(s for s in symbols if s.address == fix_p)
    key = _s16s(rel.slice_at(key_sym.address, key_sym.size))
    data = _s16s(rel.slice_at(data_sym.address, data_sym.size))
    fix = _s16s(rel.slice_at(fix_sym.address, fix_sym.size))
    tables = (flags, key, data, fix, nframes)
    _ANIM_TABLES[cache_key] = tables
    return tables


def evaluate_pose(
    rel: RelData,
    symbols: list[MapSymbol],
    anim_name: str,
    num_joints: int,
    frame: float,
) -> tuple[tuple[int, int, int], list[tuple[int, int, int]]]:
    pose_key = (id(rel), anim_name, num_joints, frame)
    cached_pose = _POSE_CACHE.get(pose_key)
    if cached_pose is not None:
        return cached_pose
    flags, key, data, fix, _frames = _anim_tables(rel, symbols, anim_name, num_joints)

    ki = 0
    fi = 0
    di = 0
    trans = [0, 0, 0]
    joint_flag = BIT_TRANS_X
    for component in range(3):
        if flags[0] & joint_flag:
            trans[component] = _key_calc(di, key[ki], data, frame)
            di += key[ki]
            ki += 1
        else:
            trans[component] = fix[fi]
            fi += 1
        joint_flag >>= 1

    rots: list[tuple[int, int, int]] = []
    for joint_i in range(num_joints):
        joint_flag = BIT_ROT_X
        xyz = [0, 0, 0]
        for component in range(3):
            if joint_flag & flags[joint_i]:
                raw = _key_calc(di, key[ki], data, frame)
                di += key[ki]
                ki += 1
            else:
                raw = fix[fi]
                fi += 1
            xyz[component] = _deg10_to_binangle(raw)
            joint_flag >>= 1
        rots.append((xyz[0], xyz[1], xyz[2]))
    result = (trans[0], trans[1], trans[2]), rots
    _POSE_CACHE[pose_key] = result
    return result


def _parents_from_children(child_counts: list[int]) -> list[int]:
    parents = [-1] * len(child_counts)
    cursor = 0

    def walk(parent: int) -> int:
        nonlocal cursor
        idx = cursor
        cursor += 1
        parents[idx] = parent
        for _ in range(child_counts[idx]):
            walk(idx)
        return idx

    walk(-1)
    return parents


def _world_matrices(
    joints: list[Joint],
    root_trans: tuple[float, float, float],
    rotations: list[tuple[int, int, int]],
) -> tuple[list[Mat4], list[Mat4]]:
    local: list[Mat4] = []
    world: list[Mat4] = []
    for i, joint in enumerate(joints):
        trans = root_trans if i == 0 else joint.translation
        local.append(local_softcv3(trans, rotations[i]))
        if joint.parent < 0:
            world.append(local[-1])
        else:
            world.append(world[joint.parent].mul(local[-1]))
    return local, world


def _mtx_slot_joints(joints: list[Joint]) -> list[int]:
    """cKF writes one Mtx per Gfx-bearing joint, in table order, at segment 0x0D."""
    return [j.index for j in joints if j.gfx_addr]


def _assign_part_joints(part: MeshPart, owner: int, mtx_joints: list[int]) -> None:
    part.joint_index = owner
    for vertex in part.vertices:
        if 0 <= vertex.mtx_index < len(mtx_joints):
            vertex.joint_index = mtx_joints[vertex.mtx_index]
        else:
            vertex.joint_index = owner


def _sits_on_y(vertices: list) -> bool:
    """True when GX verts already stand on +Y (houses/shops), unlike the +X cKF chain."""
    if not vertices:
        return False
    min_y = min(v.y for v in vertices)
    max_y = max(v.y for v in vertices)
    return min_y >= -0.05 and (max_y - min_y) >= 0.5


def select_bind_anim(prefix: str, anim_names: list[str]) -> str | None:
    """Pose used as the GLB rest. Wait clips already stand on +Y.

    Furniture/clock clips store rest yaw as constants (locker −90°, chest +90°)
    and the closed frame. Identity + `ckf_basis` double-rotates those and leaves
    drawers on the last key if Godot autoplays.
    """
    if not anim_names:
        return None
    # `kab_1` is the train sleep passenger; rest is `wait_nemu1`, not standing `wait1`.
    if prefix == "kab_1":
        nemu = next((n for n in anim_names if n.endswith("wait_nemu1")), None)
        if nemu:
            return nemu
    wait = next((n for n in anim_names if n.endswith("wait1")), None)
    if wait:
        return wait
    nemu = next((n for n in anim_names if n.endswith("wait_nemu1")), None)
    if nemu:
        return nemu
    if prefix.startswith("int_") or prefix.startswith("clk_"):
        exact = f"cKF_ba_r_{prefix}"
        return exact if exact in anim_names else anim_names[0]
    return None


def _is_y_up_structure(prefix: str) -> bool:
    """Outdoor buildings whose GX verts already sit on +Y.

    Clock hands / weather vanes push vtx min-Y below the `_sits_on_y` floor, so
    the prefix list is the source of truth. Bind the door clip (station joint-0
    is identity; house −90°, shop/myhome −135°) and skip `ckf_basis`.
    """
    m = re.match(r"^obj_[swf]_(.+)$", prefix)
    if not m:
        return False
    head = re.split(r"[\d_]", m.group(1), maxsplit=1)[0]
    return head in {"house", "myhome", "shop", "yubinkyoku", "tailor", "yamishop", "station"}


def convert_ckf_model(
    rel: RelData,
    symbols: list[MapSymbol],
    skeleton_name: str,
    scale: float,
    animation_names: list[str] | None = None,
    bank: TextureBank | None = None,
) -> ConvertedModel:
    by_name = index_by_name(symbols)
    skeleton = find_symbol(symbols, skeleton_name, by_name)
    sk_blob = rel.slice_at(skeleton.address, skeleton.size)
    num_joints = sk_blob[0]
    prefix = skeleton_name.replace("cKF_bs_r_", "")
    if num_joints == 0:
        raise ValueError(f"Empty cKF skeleton (no joints): {skeleton_name}")
    if bank is not None:
        bank.segment_images.clear()
        bank.segment_palettes.clear()
        bank.bind_model_segments(prefix)
    joints_sym = find_symbol(symbols, f"cKF_je_r_{prefix}_tbl", by_name)
    jblob = rel.slice_at(joints_sym.address, joints_sym.size)
    has_gfx = any(
        struct.unpack_from(">I", jblob, i)[0] != 0 for i in range(0, len(jblob), 12)
    )
    if not has_gfx:
        raise ValueError(f"Meshless cKF skeleton: {skeleton_name}")
    vtx_sym = _resolve_vtx_sym(prefix, symbols, by_name, rel, joints_sym)
    vertices = parse_vtx_blob(rel.slice_at(vtx_sym.address, vtx_sym.size), scale, flip_z=False)

    addr_to_sym = {s.address: s for s in symbols}
    jblob = rel.slice_at(joints_sym.address, joints_sym.size)
    raw_joints: list[tuple[int, int, int, tuple[int, int, int]]] = []
    child_counts: list[int] = []
    for i in range(0, len(jblob), 12):
        gfx, child, flags, tx, ty, tz = struct.unpack_from(">IBBhhh", jblob, i)
        raw_joints.append((gfx, child, flags, (tx, ty, tz)))
        child_counts.append(child)
    parents = _parents_from_children(child_counts)
    joints: list[Joint] = []
    for i, (gfx, child, flags, trans) in enumerate(raw_joints):
        name = addr_to_sym[gfx].name if gfx and gfx in addr_to_sym else None
        joints.append(
            Joint(
                child_count=child,
                flags=flags,
                translation=(trans[0] * scale, trans[1] * scale, trans[2] * scale),
                gfx_addr=gfx,
                model_name=name,
                parent=parents[i],
                index=i,
            )
        )

    model_syms = [
        s
        for s in symbols
        if s.name.endswith("_model") and vtx_sym.address < s.address < joints_sym.address
    ]
    parts_by_name: dict[str, list[MeshPart]] = {}
    tex_state = TextureState()
    for model in model_syms:
        # Each joint DL sets its own SETTIMG. Do not leak the previous image onto later parts.
        tex_state.img_addr = 0
        tex_state.width = 0
        tex_state.height = 0
        tex_state.prim = (255, 255, 255, 255)
        blob = rel.slice_at(model.address, model.size)
        decoded = parse_gfx(
            model.name,
            blob,
            vertices,
            bank=bank,
            state=tex_state,
            vtx_base_addr=vtx_sym.address,
        )
        mesh_parts = [p for p in decoded if p.triangles]
        if mesh_parts:
            parts_by_name[model.name] = mesh_parts

    mtx_joints = _mtx_slot_joints(joints)
    parts: list[MeshPart] = []
    for joint in joints:
        if not joint.model_name or joint.model_name not in parts_by_name:
            continue
        for part in parts_by_name[joint.model_name]:
            _assign_part_joints(part, joint.index, mtx_joints)
            parts.append(part)
    assigned = {p.name.split(":")[0] for p in parts}
    # Villager house1 keeps `*_windowL/R_model` off the skeleton (joint 7 is NULL) and
    # emits them on SHADOW_DISP with that joint's matrix (`ac_house_draw`).
    window_host = next((j for j in reversed(joints) if j.model_name is None and j.index > 0), None)
    if window_host is not None:
        for suffix in ("window_model", "windowL_model", "windowR_model"):
            name = f"{prefix}_{suffix}"
            if name in assigned or name not in by_name:
                continue
            mesh_parts = parts_by_name.get(name)
            if not mesh_parts:
                tex_state.img_addr = 0
                tex_state.width = 0
                tex_state.height = 0
                tex_state.prim = (255, 255, 255, 255)
                model = by_name[name]
                mesh_parts = [
                    p
                    for p in parse_gfx(
                        model.name,
                        rel.slice_at(model.address, model.size),
                        vertices,
                        bank=bank,
                        state=tex_state,
                        vtx_base_addr=vtx_sym.address,
                    )
                    if p.triangles
                ]
            for part in mesh_parts:
                _assign_part_joints(part, window_host.index, mtx_joints)
                parts.append(part)
    if not parts:
        if all(j.gfx_addr == 0 for j in joints):
            raise ValueError(f"Meshless cKF skeleton: {skeleton_name}")
        raise ValueError(f"No mesh parts decoded for {skeleton_name}")

    anim_names = list(animation_names or [])
    anim_names.sort(key=lambda n: (0 if n.endswith("wait1") else 1, n))
    identity_rot = [(0, 0, 0)] * num_joints
    sits_y = _sits_on_y(vertices) or _is_y_up_structure(prefix)
    # Player wait clips put ~90° on joint 0 (stand the +X chain on +Y).
    # Furniture clips already include rest yaw (degrees×10 constants) — bake frame 1
    # (closed). Do not add ckf_basis on top. Houses/shops sit on +Y; door clips
    # store rest yaw on joint 0 (house −90°, shop/myhome −135°).
    use_anim_bind = False
    use_wait_bind = False
    root_t = (0.0, 0.0, 0.0)
    bind_rots = identity_rot
    bind_anim = select_bind_anim(prefix, anim_names)
    if bind_anim is None and sits_y and anim_names:
        exact = f"cKF_ba_r_{prefix}"
        bind_anim = exact if exact in anim_names else anim_names[0]
    if bind_anim is not None:
        try:
            root_raw, bind_rots = evaluate_pose(rel, symbols, bind_anim, num_joints, 1.0)
            root_t = (root_raw[0] * scale, root_raw[1] * scale, root_raw[2] * scale)
            use_anim_bind = True
            use_wait_bind = bind_anim.endswith("wait1") or bind_anim.endswith("wait_nemu1")
        except (KeyError, StopIteration, struct.error, ValueError, IndexError):
            bind_rots = identity_rot
            root_t = (0.0, 0.0, 0.0)
    bind_local, bind_world = _world_matrices(joints, root_t, bind_rots)
    if use_anim_bind or sits_y:
        basis = Mat4.identity()
    else:
        basis = ckf_basis()
    bind_world = [basis.mul(w) for w in bind_world]
    bind_local_g: list[Mat4] = []
    for joint in joints:
        if joint.parent < 0:
            bind_local_g.append(bind_world[joint.index])
        else:
            bind_local_g.append(bind_world[joint.parent].inverse_affine().mul(bind_world[joint.index]))
    bind_local = bind_local_g

    animations: dict[str, list[AnimChannel]] = {}
    for anim_name in anim_names:
        try:
            _flags, _key, _data, _fix, nframes = _anim_tables(rel, symbols, anim_name, num_joints)
            channels = [
                AnimChannel(times=[], translations=[], rotations=[]) for _ in joints
            ]
            for frame_i in range(1, nframes + 1):
                t = (frame_i - 1) / FPS
                root_raw, rots = evaluate_pose(rel, symbols, anim_name, num_joints, float(frame_i))
                root_scaled = (root_raw[0] * scale, root_raw[1] * scale, root_raw[2] * scale)
                _locals_f, worlds_f = _world_matrices(joints, root_scaled, rots)
                worlds_g = [basis.mul(w) for w in worlds_f]
                for ji, joint in enumerate(joints):
                    if joint.parent < 0:
                        local_g = worlds_g[ji]
                    else:
                        local_g = worlds_g[joint.parent].inverse_affine().mul(worlds_g[ji])
                    channels[ji].times.append(t)
                    channels[ji].translations.append(local_g.translation())
                    channels[ji].rotations.append(local_g.rotation_quat())
            short = anim_name.replace("cKF_ba_r_", "")
            animations[short] = channels
        except (KeyError, StopIteration, struct.error, ValueError, IndexError):
            continue

    if use_wait_bind:
        z_axis = "wait_bind"
    elif sits_y and use_anim_bind:
        z_axis = "gx_y_up anim_bind (joint-0 yaw from door clip)"
    elif sits_y:
        z_axis = "gx_y_up"
    else:
        z_axis = "ckf_bind_to_godot (+90° about Z)"

    return ConvertedModel(
        parts=parts,
        joints=joints,
        bind_local=bind_local,
        bind_world=bind_world,
        animations=animations,
        extras={
            "source_skeleton": skeleton_name,
            "scale": scale,
            "z_axis": z_axis,
            "use_wait_bind": use_wait_bind,
            "use_anim_bind": use_anim_bind,
        },
    )


def _overlay_mat_name(gfx_name: str, by_name: dict[str, MapSymbol]) -> str | None:
    """Geometry-only Gfx that bg_item textures with a shared material first.

    `tree4_ap_list` uses `apple_DL_mode` then `obj_s_tree5_apple_appleT_gfx_model`.
    `palm5_coco_list` uses `obj_item_cocoT_mat_model` then `obj_*_palm5_cocoT_gfx_model`.
    Orange/peach/pear/nuts/bag share the apple overlay verts and swap `*_DL_mode`.
    ROCK_B–E share ROCK_A's CI4: `stone_a_list` displays `stone_DL_table[0]`
    (`obj_*_stoneA_mat_model`) then `table[1 + sub_idx]` (B=1 … E=4).
    Holes: `hole00_g_list` displays `obj_hole0T_g_mat_model` then
    `obj_hole{N}T_gfx_model`. There is no `obj_hole0T_mat_model`.
    """
    if "tree5_apple" in gfx_name and "apple_DL_mode" in by_name:
        return "apple_DL_mode"
    if "palm5_coco" in gfx_name and "obj_item_cocoT_mat_model" in by_name:
        return "obj_item_cocoT_mat_model"
    m = re.match(r"^(obj_[swf]_stone)[B-E]_gfx_model$", gfx_name)
    if m:
        cand = f"{m.group(1)}A_mat_model"
        if cand in by_name:
            return cand
    if re.match(r"^obj_hole\d+T_gfx_model$", gfx_name):
        for cand in ("obj_hole0T_g_mat_model", "obj_hole0T_s_mat_model"):
            if cand in by_name:
                return cand
    return None


def _mat_model_name(gfx_name: str, by_name: dict[str, MapSymbol]) -> str | None:
    """Resolve `*_gfx_model` → material DL. Some summer trees only ship a gold mat."""
    candidates: list[str] = []
    if "_gfx_model" in gfx_name:
        candidates.append(gfx_name.replace("_gfx_model", "_mat_model"))
    elif gfx_name.endswith("_model"):
        candidates.append(gfx_name[: -len("_model")] + "_mat_model")
    # obj_s_tree3_leafT has only obj_s_gold_tree3_leafT_mat_model on the US disc.
    for name in list(candidates):
        if "_gold_" in name:
            continue
        # obj_s_tree3_leafT_mat_model → obj_s_gold_tree3_leafT_mat_model
        parts = name.split("_", 2)
        if len(parts) >= 3 and parts[0] == "obj" and parts[1] in ("s", "w", "f"):
            candidates.append(f"obj_{parts[1]}_gold_{parts[2]}")
    for name in candidates:
        if name in by_name:
            return name
    return _overlay_mat_name(gfx_name, by_name)


def _g_vtx_targets(rel: RelData, symbols: list[MapSymbol], by_name: dict[str, MapSymbol], gfx_names: list[str]) -> set[int]:
    targets: set[int] = set()
    for name in gfx_names:
        model = find_symbol(symbols, name, by_name)
        blob = rel.slice_at(model.address, model.size)
        for off in range(0, len(blob) - 7, 8):
            w0, w1 = struct.unpack_from(">II", blob, off)
            if w0 >> 24 == G_VTX:
                targets.add(w1)
    return targets


def _vtx_sym_containing(targets: set[int], symbols: list[MapSymbol]) -> MapSymbol | None:
    if not targets:
        return None
    for sym in symbols:
        if not sym.name.endswith("_v") or sym.name.startswith("cKF_"):
            continue
        if sym.obj != "dataobject.obj":
            continue
        if any(sym.address <= addr < sym.end for addr in targets):
            return sym
    return None


def _vtx_sym_for_gfx(
    rel: RelData,
    symbols: list[MapSymbol],
    by_name: dict[str, MapSymbol],
    vtx_name: str,
    gfx_names: list[str],
) -> MapSymbol:
    """Pick the Vtx blob the display lists actually point at.

    `dataobject.obj` ships the same static array under one name more than once — the
    inventory icon and the in-world model each get their own `tol_uki_1_v` — and a
    by-name lookup silently returns the wrong one, decoding zero triangles. Summer
    palms draw `obj_s_palm1T_gfx_model` from `obj_w_palm1_v`, not `obj_s_palm1_v`.
    """
    targets = _g_vtx_targets(rel, symbols, by_name, gfx_names)
    candidates = [s for s in symbols if s.name == vtx_name]
    if targets:
        for sym in candidates:
            if any(sym.address <= addr < sym.end for addr in targets):
                return sym
        cross = _vtx_sym_containing(targets, symbols)
        if cross is not None:
            return cross
    if len(candidates) == 1:
        return candidates[0]
    if len(candidates) > 1:
        for sym in candidates:
            if sym.obj == "dataobject.obj":
                return sym
        return candidates[0]
    return find_symbol(symbols, vtx_name, by_name)


## cKF skeleton prefix → REL vtx when names diverge (`obj_train1_3` → `obj_train_3_v`).
_CKF_VTX_ALIASES: dict[str, str] = {
    "obj_train1_3": "obj_train_3_v",
}


def _resolve_vtx_sym(
    prefix: str,
    symbols: list[MapSymbol],
    by_name: dict[str, MapSymbol],
    rel: RelData,
    joints_sym: MapSymbol,
) -> MapSymbol:
    alias = _CKF_VTX_ALIASES.get(prefix)
    if alias and alias in by_name:
        return by_name[alias]
    primary = f"{prefix}_v"
    if primary in by_name and by_name[primary].obj == "dataobject.obj":
        return by_name[primary]
    jblob = rel.slice_at(joints_sym.address, joints_sym.size)
    addr_to_sym = {s.address: s for s in symbols}
    gfx_names: list[str] = []
    for i in range(0, len(jblob), 12):
        gfx, _child, _flags, *_rest = struct.unpack_from(">IBBhhh", jblob, i)
        if gfx and gfx in addr_to_sym:
            gfx_names.append(addr_to_sym[gfx].name)
    cross = _vtx_sym_containing(_g_vtx_targets(rel, symbols, by_name, gfx_names), symbols)
    if cross is not None:
        return cross
    return find_symbol(symbols, primary, by_name)


def convert_static_gfx(
    rel: RelData,
    symbols: list[MapSymbol],
    vtx_name: str,
    gfx_names: list[str],
    scale: float,
    bank: TextureBank | None = None,
) -> list[MeshPart]:
    by_name = index_by_name(symbols)
    vtx_sym = _vtx_sym_for_gfx(rel, symbols, by_name, vtx_name, gfx_names)
    vertices = parse_vtx_blob(rel.slice_at(vtx_sym.address, vtx_sym.size), scale, flip_z=False)
    parts: list[MeshPart] = []
    tex_state = TextureState()
    for name in gfx_names:
        if bank is not None:
            bank.current_gfx = name
        mat_name = _mat_model_name(name, by_name)
        if bank is not None and mat_name is not None:
            mat = by_name[mat_name]
            apply_texture_commands(rel.slice_at(mat.address, mat.size), bank, tex_state)
        model = find_symbol(symbols, name, by_name)
        blob = rel.slice_at(model.address, model.size)
        decoded = parse_gfx(
            model.name,
            blob,
            vertices,
            bank=bank,
            state=tex_state,
            vtx_base_addr=vtx_sym.address,
        )
        parts.extend(p for p in decoded if p.triangles)
    if not parts:
        raise ValueError(f"No mesh parts decoded for {vtx_name}")
    return parts
