from __future__ import annotations

import re
import struct
from dataclasses import dataclass, field

from .gfx import G_SETTIMG, G_VTX, MeshPart, RenderState, apply_texture_commands, parse_gfx, parse_vtx_blob
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

    def table(addr: int) -> list[int]:
        ## A clip whose every channel is constant (`ply_1_umbrella1`, the held-umbrella pose)
        ## has NULL key / data tables — only the fixed table.
        if addr == 0:
            return []
        ## Code from another module can share the address (`aTUT_actor_ct` vs
        ## `cKF_c_ply_1_umbrella1_tbl`): prefer a symbol from the clip header's own object.
        at = [s for s in symbols if s.address == addr]
        named = [s for s in at if not s.name.startswith(".")]
        same_obj = [s for s in named if s.obj == header.obj]
        sym = (same_obj or named or at)[0]
        return _s16s(rel.slice_at(sym.address, sym.size))

    key = table(key_p)
    data = table(data_p)
    fix = table(fix_p)
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


## Reject +X-chain meshes (characters / trains in bind) that are long along X.
_SITS_Y_X_CHAIN_RATIO = 1.75
_SITS_Y_FLOOR = -0.05
_SITS_Y_MIN_HEIGHT = 0.5
## Tent vanes / clock hands can dunk >5% of verts; majority still sits on the floor.
_SITS_Y_FLOOR_FRAC = 0.90


def _percentile(sorted_vals: list[float], p: float) -> float:
    if not sorted_vals:
        return 0.0
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    idx = int(p * (len(sorted_vals) - 1))
    return sorted_vals[max(0, min(idx, len(sorted_vals) - 1))]


def _sits_on_y(vertices: list) -> bool:
    """True when GX verts already stand on +Y (structures), unlike the +X cKF chain.

    Floor: 5th-percentile Y above the pad, **or** ≥90% of verts above it (player
    tent vanes dunk more than 5%). Rejects meshes whose AABB is long along +X.
    """
    if not vertices:
        return False
    ys = sorted(v.y for v in vertices)
    p05 = _percentile(ys, 0.05)
    height = ys[-1] - ys[0]
    if height < _SITS_Y_MIN_HEIGHT:
        return False
    frac_ok = sum(1 for y in ys if y >= _SITS_Y_FLOOR) / len(ys) >= _SITS_Y_FLOOR_FRAC
    if p05 < _SITS_Y_FLOOR and not frac_ok:
        return False
    xs = [v.x for v in vertices]
    zs = [v.z for v in vertices]
    extent_x = max(xs) - min(xs)
    extent_y = height
    extent_z = max(zs) - min(zs)
    if extent_x > _SITS_Y_X_CHAIN_RATIO * max(extent_y, extent_z):
        return False
    return True


## A pose "stands" the skeleton when its joint chain points this much more along +Y than
## sideways (identity cKF binds lie along +X).
_STANDS_CHAIN_RATIO = 2.0


def _chain_vector(joints: list[Joint], rotations: list[tuple[int, int, int]]) -> tuple[float, float, float]:
    """Sum of joint positions relative to the root: which way the skeleton's chain points."""
    _local, world = _world_matrices(joints, (0.0, 0.0, 0.0), rotations)
    sx = sy = sz = 0.0
    for w in world[1:]:
        x, y, z = w.transform_point(0.0, 0.0, 0.0)
        sx += x
        sy += y
        sz += z
    return sx, sy, sz


def pose_stands_chain(joints: list[Joint], rotations: list[tuple[int, int, int]]) -> bool:
    """True when this pose turns a +X-lying bind chain up onto +Y by itself.

    Such a clip already does what `ckf_basis` would (the house gyroid's `hnw_move` holds the
    body joint at 90° Z), so baking it on top of the basis lays the model on its side.
    """
    identity = [(0, 0, 0)] * len(joints)
    ix, iy, iz = _chain_vector(joints, identity)
    if ix <= _STANDS_CHAIN_RATIO * max(abs(iy), abs(iz)):
        return False
    px, py, pz = _chain_vector(joints, rotations)
    return py > _STANDS_CHAIN_RATIO * max(abs(px), abs(pz))


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


def select_close_bind(anim_names: list[str], prefix: str | None = None) -> str | None:
    """Prefer a closed rest clip when no wait/furniture bind applies (trains, doors).

    `*_close` wins when present (outdoor caboose). Vestibule `obj_romtrain_door` ships
    only `cKF_ba_r_{prefix}` — closed at frame 1, no `_close` suffix. Without that
    fallback the GLB rests on bare `ckf_basis` and the panel floats above the camera.

    `act_*` actors (museum fish `act_mus_*`, `act_bee`, `act_balloon`, stag beetles)
    also ship a single `cKF_ba_r_{prefix}` loop, but those keep the `ckf_basis`
    stand-up: their draw code (`museum_fish_visual` `SWIM_FROM_STAND`, …) rotates
    the standing mesh into place. An identity bind lays them on their side.
    """
    close = next((n for n in anim_names if n.endswith("_close")), None)
    if close:
        return close
    if prefix and not prefix.startswith("act_"):
        exact = f"cKF_ba_r_{prefix}"
        if exact in anim_names:
            return exact
    return None


def bind_frame_for_anim(anim_name: str, nframes: int) -> float:
    """Frame sampled into the GLB rest pose.

    Wait/furniture clips store the closed/standing pose at frame 1. `*_close`
    clips animate open → closed (`obj_train1_3_close` is 32 frames), so rest is
    the last frame — frame 1 of close is the open door.
    """
    if anim_name.endswith("_close") and nframes > 0:
        return float(nframes)
    return 1.0


def _blob_sets_texture(blob: bytes) -> bool:
    """True if this Gfx blob issues its own `G_SETTIMG` (real hardware only reloads
    TMEM/SETTIMG when told to — everything else inherits the previous DL's state)."""
    for off in range(0, len(blob) - 7, 8):
        if (struct.unpack_from(">I", blob, off)[0] >> 24) == G_SETTIMG:
            return True
    return False


def _joint_gfx_index(symbols: list[MapSymbol], joints_sym: MapSymbol) -> dict[int, MapSymbol]:
    """Address → symbol for a joint table's Gfx pointers, from the table's own object.

    The map lists every object's symbols in one address space, so a REL data DL can
    share its number with unrelated code (`Lfoot1_bul_model` and `m_player.o`'s
    `Player_actor_request_main_demo_geton_train` are both 0x18d858). Last-wins picked the
    function, the joint lost its model name, and the thigh DL was walked as a loose part
    with reset texture state — the bull's left thigh vanished. Section labels (`.data`)
    never name a DL.
    """
    out: dict[int, MapSymbol] = {}
    for sym in symbols:
        if sym.obj != joints_sym.obj or sym.name.startswith("."):
            continue
        out[sym.address] = sym  # same tie-break as before within the object
    return out


def convert_ckf_model(
    rel: RelData,
    symbols: list[MapSymbol],
    skeleton_name: str,
    scale: float,
    animation_names: list[str] | None = None,
    bank: TextureBank | None = None,
    texture_prefix: str | None = None,
) -> ConvertedModel:
    """`texture_prefix` binds another draw entry's texture set (`bul_2` on the `bul_1`
    skeleton) — villagers of one species share a skeleton but not their textures."""
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
        ## Names are keyed by segment, not model: a prior skeleton's face bind
        ## (`mka_1_face`) or dummy-image stand-in would otherwise relabel this
        ## model's eye/mouth quads and hide them from `NpcFace`. Matches the
        ## reset `_convert_static` does before `bind_static_segments`.
        bank._segment_offset_names.clear()
        bank.bind_model_segments(texture_prefix or prefix)
    joints_sym = find_symbol(symbols, f"cKF_je_r_{prefix}_tbl", by_name)
    jblob = rel.slice_at(joints_sym.address, joints_sym.size)
    has_gfx = any(
        struct.unpack_from(">I", jblob, i)[0] != 0 for i in range(0, len(jblob), 12)
    )
    if not has_gfx:
        raise ValueError(f"Meshless cKF skeleton: {skeleton_name}")
    vtx_sym = _resolve_vtx_sym(prefix, symbols, by_name, rel, joints_sym)
    vertices = parse_vtx_blob(rel.slice_at(vtx_sym.address, vtx_sym.size), scale, flip_z=False)

    addr_to_sym = _joint_gfx_index(symbols, joints_sym)
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
    ## Process joint-owned models in *joint/draw* order, not address order: some child
    ## joints' Gfx (e.g. `obj_s_post_flag_saki_model`, the mailbox flag's tip half) has
    ## no texture/combine/prim commands of its own at all and relies on inheriting
    ## whatever the previous joint left bound — exactly like the real RDP's SETTIMG/PRIM
    ## registers, which persist across DLs until explicitly rewritten. Address order can
    ## place such a joint's Gfx *before* the sibling it inherits from in the file, which
    ## silently drops its geometry (no texture context to decode against). Models not
    ## tied to a joint (unused alt frames, the `window_host` fallback below) keep the
    ## old address-order/fresh-state behavior, appended after the joint chain.
    joint_order = {j.model_name: j.index for j in joints if j.model_name}
    model_syms = sorted(
        model_syms,
        key=lambda s: (0, joint_order[s.name]) if s.name in joint_order else (1, s.address),
    )
    parts_by_name: dict[str, list[MeshPart]] = {}
    tex_state = TextureState()
    for model in model_syms:
        blob = rel.slice_at(model.address, model.size)
        if model.name not in joint_order or _blob_sets_texture(blob):
            # Either a standalone (non-chained) model, or one that rebinds its own
            # texture — reset so a previous image doesn't leak onto unrelated parts.
            tex_state.img_addr = 0
            tex_state.width = 0
            tex_state.height = 0
            tex_state.prim = (255, 255, 255, 255)
            tex_state.prim_set = False
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
                tex_state.prim_set = False
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
    sits_y = _sits_on_y(vertices)
    # Player wait clips put ~90° on joint 0 (stand the +X chain on +Y).
    # Furniture clips already include rest yaw (degrees×10 constants) — bake frame 1
    # (closed). Do not add ckf_basis on top. Y-up structures bake door-clip joint-0 yaw.
    use_anim_bind = False
    use_wait_bind = False
    root_t = (0.0, 0.0, 0.0)
    bind_rots = identity_rot
    bind_anim = select_bind_anim(prefix, anim_names)
    if bind_anim is None and sits_y and anim_names:
        exact = f"cKF_ba_r_{prefix}"
        bind_anim = exact if exact in anim_names else anim_names[0]
    ## Prefer `*_close` or exact `cKF_ba_r_{prefix}` (trains, vestibule door).
    ## Successful anim bind uses identity basis — joint-0 ±90° stands the +X chain.
    if bind_anim is None:
        bind_anim = select_close_bind(anim_names, prefix)
    ## Only clip(s) stand the chain up themselves (house gyroid): bake frame 1, no basis.
    if bind_anim is None and not prefix.startswith("act_"):
        for name in anim_names:
            try:
                _root, rots = evaluate_pose(rel, symbols, name, num_joints, 1.0)
            except (KeyError, StopIteration, struct.error, ValueError, IndexError):
                continue
            if pose_stands_chain(joints, rots):
                bind_anim = name
                break
    if bind_anim is not None:
        try:
            _flags, _key, _data, _fix, nframes = _anim_tables(
                rel, symbols, bind_anim, num_joints
            )
            bind_frame = bind_frame_for_anim(bind_anim, nframes)
            root_raw, bind_rots = evaluate_pose(
                rel, symbols, bind_anim, num_joints, bind_frame
            )
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
    Buried deposit X marks (`crack00_*_list`) reuse the same hole verts/gfx with
    `obj_crack0T_*_mat_model` — pass `mat=` into `convert_static_gfx` for that.
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


def _mat_model_name(
    gfx_name: str, by_name: dict[str, MapSymbol], mat_override: str | None = None
) -> str | None:
    """Resolve `*_gfx_model` → material DL. Some summer trees only ship a gold mat."""
    if mat_override and mat_override in by_name:
        return mat_override
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
    addr_to_sym = _joint_gfx_index(symbols, joints_sym)
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
    mat_override: str | None = None,
) -> list[MeshPart]:
    by_name = index_by_name(symbols)
    vtx_sym = _vtx_sym_for_gfx(rel, symbols, by_name, vtx_name, gfx_names)
    vertices = parse_vtx_blob(rel.slice_at(vtx_sym.address, vtx_sym.size), scale, flip_z=False)
    parts: list[MeshPart] = []
    ## Share texture + render-mode state across sequential DLs so `*_setmode` /
    ## `*_DL_mode` keep SETTIMG / SetRenderMode when the following vtx DL draws.
    ## Reset when a companion `*_mat_model` starts a new material (axe/coco style).
    tex_state = TextureState()
    render_state = RenderState()
    for name in gfx_names:
        if bank is not None:
            bank.current_gfx = name
        mat_name = _mat_model_name(name, by_name, mat_override)
        if bank is not None and mat_name is not None:
            tex_state = TextureState()
            render_state = RenderState()
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
            render=render_state,
        )
        parts.extend(p for p in decoded if p.triangles)
    if not parts:
        raise ValueError(f"No mesh parts decoded for {vtx_name}")
    return parts
