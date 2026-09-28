class_name BugProgram
extends RefCounted

## Base for the 14 `aINS_PROGRAM_*` movement overlays (`ac_ins_*.c`). One instance
## per live `BugActor`. `BugActor` runs the shared per-frame framework
## (`aINS_actor_move`) then calls `actor_move()` here — the program's state machine
## (`*_actor_move` → `action_proc`). Subclasses live beside this file.
##
## Angles: decomp uses s16 (0..65535, wrapping). We keep radians; `MLib.S16` converts a
## decomp step (`0x800` etc.) to radians. Distances are GX unless noted.


## `aINS_INSECT_TYPE_*` for readability inside the overlays.
const T_COMMON_BUTTERFLY := 0
const T_YELLOW_BUTTERFLY := 1
const T_TIGER_BUTTERFLY := 2
const T_PURPLE_BUTTERFLY := 3
const T_ROBUST_CICADA := 4
const T_WALKER_CICADA := 5
const T_EVENING_CICADA := 6
const T_BROWN_CICADA := 7
const T_BEE := 8
const T_COMMON_DRAGONFLY := 9
const T_RED_DRAGONFLY := 10
const T_DARNER_DRAGONFLY := 11
const T_BANDED_DRAGONFLY := 12
const T_LONG_LOCUST := 13
const T_MIGRATORY_LOCUST := 14
const T_CRICKET := 15
const T_GRASSHOPPER := 16
const T_BELL_CRICKET := 17
const T_PINE_CRICKET := 18
const T_DRONE_BEETLE := 19
const T_DYNASTID_BEETLE := 20
const T_FLAT_STAG_BEETLE := 21
const T_JEWEL_BEETLE := 22
const T_LONGHORN_BEETLE := 23
const T_LADYBUG := 24
const T_SPOTTED_LADYBUG := 25
const T_MANTIS := 26
const T_FIREFLY := 27
const T_COCKROACH := 28
const T_SAW_STAG_BEETLE := 29
const T_MOUNTAIN_BEETLE := 30
const T_GIANT_BEETLE := 31
const T_SNAIL := 32
const T_MOLE_CRICKET := 33
const T_POND_SKATER := 34
const T_BAGWORM := 35
const T_PILL_BUG := 36
const T_SPIDER := 37
const T_ANT := 38
const T_MOSQUITO := 39
const T_SPIRIT := 40


## Called once from `BugActor.create()` after shared setup. `released` mirrors
## `actor->actor_specific` (0 = field spawn, 1 = net release / `aINS_MAKE_EXIST`).
func actor_init(_a: BugActor, _released: bool) -> void:
	pass


## `mv_proc` — the per-frame state-machine entry. Default routes to `action_proc`.
func actor_move(a: BugActor, sense: BugActor.Sense) -> void:
	if a.action_proc.is_valid():
		a.action_proc.call(a, sense)


## Draw pose. `aINS_actor_draw`: `(int)insect->_1E0` (0 or 1) for most; overlays that
## keep a still idle return 0.
func pose_index(a: BugActor) -> int:
	return int(a.anime0) & 1


## Net release (`aINS_make_actor` → `actor_specific = 1`). Default: mark terminal so
## `alpha_time` fades it out.
func on_release(a: BugActor) -> void:
	a.life_time = 0
	a.alpha_time = 0x50
	a.f_bit2 = true


## `*_setupAction`: switch action, install its `action_proc`, run its `*_init`.
## Subclasses override.
func setup_action(_a: BugActor, _action: int) -> void:
	pass


## True when the type flees at patience >= 90 rather than > 90 (flyers).
func flees_at_ninety(_a: BugActor) -> bool:
	return false


# ---- field units / acres (`mFI_*`) ---------------------------------------

const UNIT_GX := BugActor.UNIT_GX
const ACRE_GX := BugActor.ACRE_GX
const ACRE_UNITS := 16
## Without a grid, units are laid out like the default one-acre `WorldGrid` (origin −320 GX).
const NO_GRID_ORIGIN_GX := -0.5 * ACRE_GX


## `mFI_Wpos2UtNum`: the field unit (grid cell) under `pos_gx`.
static func unit_of(sense: BugActor.Sense, pos_gx: Vector3) -> Vector2i:
	if sense != null and sense.grid != null:
		return sense.grid.world_to_cell(pos_gx * BugActor.GX_M)
	return Vector2i(
		floori((pos_gx.x - NO_GRID_ORIGIN_GX) / UNIT_GX),
		floori((pos_gx.z - NO_GRID_ORIGIN_GX) / UNIT_GX)
	)


## `mFI_Wpos2UtNum_inBlock`: the unit's 0..15 index inside its acre.
static func unit_in_block(cell: Vector2i) -> Vector2i:
	return Vector2i(posmod(cell.x, ACRE_UNITS), posmod(cell.y, ACRE_UNITS))


## `mFI_UtNum2CenterWpos`: centre of a unit, GX (y = 0).
static func unit_center(sense: BugActor.Sense, cell: Vector2i) -> Vector3:
	if sense != null and sense.grid != null:
		var w: Vector3 = sense.grid.cell_to_world(cell) / BugActor.GX_M
		return Vector3(w.x, 0.0, w.z)
	return Vector3(
		NO_GRID_ORIGIN_GX + (float(cell.x) + 0.5) * UNIT_GX,
		0.0,
		NO_GRID_ORIGIN_GX + (float(cell.y) + 0.5) * UNIT_GX
	)


## `mFI_BkNum2WposXZ(block) + mFI_BK_WORLDSIZE_HALF`: centre of the acre the insect was
## born in (`actor->block_x/z` never changes), cached on the actor once a grid is known.
static func acre_center(a: BugActor, sense: BugActor.Sense) -> Vector2:
	if a.acre_center_gx != Vector2.INF:
		return a.acre_center_gx
	var cell: Vector2i = unit_of(sense, a.home)
	var corner := Vector2i(
		floori(float(cell.x) / ACRE_UNITS) * ACRE_UNITS, floori(float(cell.y) / ACRE_UNITS) * ACRE_UNITS
	)
	var c: Vector3 = unit_center(sense, corner)
	var out: Vector2 = Vector2(c.x, c.z) + Vector2.ONE * (0.5 * ACRE_GX - 0.5 * UNIT_GX)
	if sense != null and sense.grid != null:
		a.acre_center_gx = out  ## only cache once the field grid is known
	return out


## `mFI_GetUnitFG` owner: same acre as the spawn (`actor->block_x/z == block_table`).
static func in_home_acre(a: BugActor, sense: BugActor.Sense, pos_gx: Vector3) -> bool:
	var c: Vector2 = acre_center(a, sense)
	return absf(pos_gx.x - c.x) < 0.5 * ACRE_GX and absf(pos_gx.z - c.y) < 0.5 * ACRE_GX


## `mCoBG_GetBgY_OnlyCenter_FromWpos(pos, 0)` — unit centre height, GX.
static func center_y(sense: BugActor.Sense, pos_gx: Vector3, fallback: float) -> float:
	if sense == null:
		return fallback
	return BugBg.unit_center_y(sense.grid, sense.layout, pos_gx, fallback)


## Front wall along the insect's travel heading within its `bg_range`.
static func wall_front(a: BugActor, sense: BugActor.Sense, range_gx: float = -1.0) -> bool:
	if sense == null or sense.grid == null:
		return false
	var r: float = a.bg_range if range_gx < 0.0 else range_gx
	return BugBg.wall_front(sense.grid, sense.layout, a.pos, a.angle_y, maxf(r, 1.0))


## `*_chk_water_attr`: on the ground and the point `bg_range + speed` ahead is water.
static func water_ahead(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense == null or sense.grid == null:
		return false
	if sense.ground.is_valid() and not a.bg_on_ground:
		return false
	var d: float = a.bg_range + a.speed
	var ahead: Vector3 = a.pos + Vector3(sin(a.angle_y) * d, 0.0, cos(a.angle_y) * d)
	return BugBg.water_at(sense.grid, ahead)


## `mCoBG_GetWaterHeight`: the water surface at the insect, or −1e9 on dry land.
static func water_y(a: BugActor, sense: BugActor.Sense) -> float:
	if sense == null or not sense.bg.is_valid():
		return -1e9
	return float(sense.bg.call(a.pos).get("water_y", -1e9))


# ---- tree trunks (`init_posY` / `init_posZ` of SEMI / KABUTO / GOKI) ----------

## Climb above the unit's keep height and Z offset for [broadleaf, cedar].
const TRUNK_CLIMB := [35.0, 30.0]
const TRUNK_Z := [-2.0, 8.0]


## Place a trunk-clinging insect for a broadleaf tree at init (the FG is not known yet).
static func cling_to_trunk(a: BugActor) -> void:
	a.pos.y = a.home.y + TRUNK_CLIMB[0]
	a.pos.z += TRUNK_Z[0]
	a.home = a.pos


## First frame with the field: a plain grown cedar (`*fg == CEDAR_TREE`) holds its insect
## 5 GX lower and 10 GX further south. Returns true when it moved.
static func settle_on_cedar(a: BugActor, sense: BugActor.Sense) -> bool:
	if sense == null or sense.layout == null:
		return false
	if not BugBg.is_cedar(sense.layout, unit_of(sense, a.home)):
		return false
	a.pos.y += TRUNK_CLIMB[1] - TRUNK_CLIMB[0]
	a.pos.z += TRUNK_Z[1] - TRUNK_Z[0]
	a.home = a.pos
	a.last_pos = a.pos
	return true


static func raining() -> bool:
	return Game != null and Game.weather == &"rain"


# ---- player tool checks (`mPlib_Check_*`) --------------------------------

## `mPlib_Check_StopNet(&pos)`: the net's position (GX) on the tick a swing stops, else INF.
static func net_stop_pos(sense: BugActor.Sense) -> Vector3:
	if sense == null or not sense.net_swing_active or sense.net_swing_origin == Vector3.INF:
		return Vector3.INF
	return sense.net_swing_origin / BugActor.GX_M


## `mPlib_Check_DigScoop(&pos)`: the unit the shovel is digging / striking (GX), else INF.
static func scoop_pos(sense: BugActor.Sense) -> Vector3:
	if sense == null or sense.player_action_cell.x < 0:
		return Vector3.INF
	match sense.player_action:
		BugActor.PlAct.DIG_SCOOP, BugActor.PlAct.REFLECT_SCOOP:
			return unit_center(sense, sense.player_action_cell)
	return Vector3.INF


## `mPlib_Check_HitAxe(&pos)`: a tool swing that is not a scoop — the unit in front of
## the player (GX), else INF.
static func axe_hit_pos(sense: BugActor.Sense) -> Vector3:
	if sense == null or not sense.player_swung_tool or not sense.has_player():
		return Vector3.INF
	if scoop_pos(sense) != Vector3.INF:
		return Vector3.INF
	var p: Vector3 = sense.player_position / BugActor.GX_M
	return p + Vector3(sin(sense.player_yaw), 0.0, cos(sense.player_yaw)) * UNIT_GX


## `mPlib_Check_VibUnit_OneFrame(&pos)`: an axe hit anywhere in the insect's acre.
static func vib_unit(a: BugActor, sense: BugActor.Sense) -> bool:
	var hit: Vector3 = axe_hit_pos(sense)
	if hit == Vector3.INF:
		return false
	var c: Vector2 = acre_center(a, sense)
	var ha: Vector2 = Vector2(floorf((hit.x - c.x) / ACRE_GX + 0.5), floorf((hit.z - c.y) / ACRE_GX + 0.5))
	var pa: Vector2 = Vector2(floorf((a.pos.x - c.x) / ACRE_GX + 0.5), floorf((a.pos.z - c.y) / ACRE_GX + 0.5))
	return ha == pa


## `SQ(dx) + SQ(dz) < SQ(r)` against a tool position (INF never matches).
static func near_xz(a: BugActor, p: Vector3, r: float) -> bool:
	if p == Vector3.INF:
		return false
	return Vector2(p.x - a.pos.x, p.z - a.pos.z).length_squared() < r * r


# ---- player-relative headings -------------------------------------------

## `RANDOM_CENTER_F(range)` / `(fqrand() - 0.5f) * range`.
static func rand_center(a: BugActor, range_rad: float) -> float:
	return (a._rng.randf() - 0.5) * range_rad


## `player->shape_info.rotation.y + RANDOM_CENTER_F(spread)`: the escape heading most
## overlays take (a released / caught insect goes the way the player faces). False while
## no player is known — the released init reruns once one is (`BugActor.frame`).
static func heading_from_player_facing(a: BugActor, spread_rad: float) -> bool:
	if not a.has_player_info:
		return false
	a.angle_y = wrapf(a.player_yaw + rand_center(a, spread_rad), -PI, PI)
	return true


# ---- shared math (libultra / m_lib analogs) --------------------------------

## `chase_f`: move `cur` toward `target` by at most `step` (>= 0).
static func chase_f(cur: float, target: float, step: float) -> float:
	if cur < target:
		return minf(cur + step, target)
	if cur > target:
		return maxf(cur - step, target)
	return target


## `chase_angle`: radian analog of the s16 `chase_angle` — shortest-arc chase.
## `chase_angle` scales its step by `game_GameFrame_2F` (frame × 0.5): `step × 30` per second
## whatever the frame rate, so half a step per 60 Hz frame.
static func chase_angle(cur: float, target: float, step: float) -> float:
	step /= DecompTime.TICKS_PER_FRAME
	var diff: float = wrapf(target - cur, -PI, PI)
	if absf(diff) <= step:
		return wrapf(target, -PI, PI)
	return wrapf(cur + signf(diff) * step, -PI, PI)


## `add_calc`: move `cur` by `fraction` of the gap, clamped to `max_step`, at least
## `min_step`, never past `target` (not frame-scaled).
static func add_calc(cur: float, target: float, fraction: float, max_step: float, min_step: float = 0.0) -> float:
	if cur == target:
		return cur
	var step: float = fraction * (target - cur)
	if step <= -min_step or min_step <= step:
		step = clampf(step, -max_step, max_step)
	else:
		step = min_step if step > 0.0 else -min_step
	var out: float = cur + step
	if (step > 0.0 and out > target) or (step <= 0.0 and out < target):
		out = target
	return out


## `chase_angle`'s return value: TRUE once `cur` has reached `target`.
static func angle_reached(cur: float, target: float) -> bool:
	return absf(wrapf(target - cur, -PI, PI)) < 0.5 * MLib.S16


## `search_position_angleY(from, to)` — yaw that points from `from` toward `to`.
## Decomp yaw convention: +X = sin, +Z = cos (`pos_speed = speed * {sin, cos}`).
## `mFI_Wpos2UtNum(home) != mFI_Wpos2UtNum(world)`: the insect has left the 40 GX unit it
## spawned on (a tree / flower it was clinging to).
static func left_home_unit(a: BugActor) -> bool:
	return (
		floori(a.home.x / 40.0) != floori(a.pos.x / 40.0)
		or floori(a.home.z / 40.0) != floori(a.pos.z / 40.0)
	)


static func angle_to(from: Vector3, to: Vector3) -> float:
	return atan2(to.x - from.x, to.z - from.z)


## `atans_table(dz, dx)` in decomp order → radian yaw (dx = sin term, dz = cos term).
static func atans(dz: float, dx: float) -> float:
	return atan2(dx, dz)


static func dist_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func deg2s(deg: float) -> float:
	## `DEG2SHORT_ANGLE2` then to radians == plain deg→rad, kept for provenance.
	return deg_to_rad(deg)


## `move_proc` for a HIDE/DUG state — the actor is a frozen point in the ground.
static func freeze_move(a: BugActor) -> void:
	a.last_pos = a.pos
	a.speed = 0.0
	a.pos_speed = Vector3.ZERO


# ---- factory --------------------------------------------------------------

static func create(program: int) -> BugProgram:
	match program:
		BugData.Program.CHOU:
			return BugChou.new()
		BugData.Program.BATTA:
			return BugBatta.new()
		BugData.Program.TONBO:
			return BugTonbo.new()
		BugData.Program.TENTOU:
			return BugTentou.new()
		BugData.Program.HOTARU:
			return BugHotaru.new()
		BugData.Program.SEMI:
			return BugSemi.new()
		BugData.Program.KABUTO:
			return BugKabuto.new()
		BugData.Program.GOKI:
			return BugGoki.new()
		BugData.Program.HITODAMA:
			return BugHitodama.new()
		BugData.Program.AMENBO:
			return BugAmenbo.new()
		BugData.Program.KA:
			return BugKa.new()
		BugData.Program.DANGO:
			return BugDango.new()
		BugData.Program.KERA:
			return BugKera.new()
		BugData.Program.MINO:
			return BugMino.new()
		_:
			return BugChou.new()
