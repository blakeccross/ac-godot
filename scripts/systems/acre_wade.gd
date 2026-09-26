class_name AcreWade
extends RefCounted

## Crossing between acres (`mPlayer_INDEX_WADE`, `m_player_common.c_inc`). Pure, in decomp GX.
##
## Outdoors the player is walled inside the current acre, 18 GX in from each edge
## (`Player_actor_CorrectWadeBlockBorder` → `mCoBG_UniqueWallCheck`). The only way out is a
## wade: while walking / running / dashing against the wall with the stick past 0.65 toward it
## and the body within 40° of straight across (`Player_actor_Set_ScrollDemo_forWade`), the
## player is carried 18 GX into the next acre over 36 ticks on an ease-in/out curve, standing
## (`WAIT1`), ignoring the stick, while the camera scrolls. The title demo's recorded input
## keeps playing through it (`title_demo_move` runs every frame).

enum Dir { NONE, RIGHT, LEFT, UP, DOWN }

const BLOCK_GX := TownSpace.BLOCK_GX
const EDGE_GX := 18.00001
const WALL_GX := 18.0
const STICK_RANGE := 0.65
const ANGLE_RANGE := 40.0
## `mCoBG_BLOCK_BGCHECK_MODE_INTRO_DEMO` (while Nook shows the houses): player-house acres
## are walled one unit further in, and the wade trigger border moves in by the same unit.
const INTRO_INSET_GX := 40.0
## Ticks (1/60 s): 36 = 0.6 s.
const TICKS := 36.0
const ACCEL := 1.1999999
const BRAKE := 34.8
## `Player_actor_Search_exist_npc_inCircle_forWade` (not in the title demo).
const NPC_CLEAR_GX := 36.0


## `mCoBG_UniqueWallCheck` → `mCoBG_ScopeWallCheck(block, 640, 640, 18)`: keep the new
## position inside the acre the player was in, 18 GX from its edges. `inset` is the intro
## BG-check mode's extra unit on player-house acres (`block_base + 40`, size `640 − 80`).
static func confine(old_gx: Vector3, new_gx: Vector3, inset: float = 0.0) -> Vector3:
	var base: Vector2 = TownSpace.block_base(TownSpace.block_of(old_gx))
	var out := new_gx
	var lo: float = WALL_GX + inset
	var hi: float = BLOCK_GX - WALL_GX - inset
	out.x = clampf(out.x, base.x + lo, base.x + hi)
	out.z = clampf(out.z, base.y + lo, base.y + hi)
	return out


## `Player_actor_CheckAbleMoveWadeBlock`. `stick`: x right, y up (`move_percentX/Y`).
## `facing`: decomp angle as radians (0 = +Z / south, +π/2 = +X / east). `can_land(dir)`
## is `mFI_ScrollCheck` + `Player_actor_CheckAbleMoveWadeBG`. `inset`: intro BG-check mode
## (`border ∓ mFI_UNIT_BASE_SIZE_F`). `unable`: `mPlib_Get_unable_wade()` — the direction is
## reported without the landing check, and the caller cancels the wade
## (`excute_cancel_wade`).
static func direction(
	pos_gx: Vector3,
	facing: float,
	stick: Vector2,
	can_land: Callable,
	inset: float = 0.0,
	unable: bool = false,
) -> Dir:
	var local := Vector2(fposmod(pos_gx.x, BLOCK_GX), fposmod(pos_gx.z, BLOCK_GX))
	var deg: float = rad_to_deg(wrapf(facing, -PI, PI))
	var near: float = EDGE_GX + inset
	var far: float = BLOCK_GX - EDGE_GX - inset
	if stick.x > STICK_RANGE and absf(deg - 90.0) < ANGLE_RANGE:
		return _at(Dir.RIGHT, local.x >= far, can_land, unable)
	if stick.x < -STICK_RANGE and absf(deg + 90.0) < ANGLE_RANGE:
		return _at(Dir.LEFT, local.x <= near, can_land, unable)
	if stick.y > STICK_RANGE and absf(deg) > 180.0 - ANGLE_RANGE:
		return _at(Dir.UP, local.y <= near, can_land, unable)
	if stick.y < -STICK_RANGE and absf(deg) < ANGLE_RANGE:
		return _at(Dir.DOWN, local.y >= far, can_land, unable)
	return Dir.NONE


## `Player_actor_CheckAbleMoveDemoWadeBlock` (a demo walk that is moving): wade whichever
## edge the body faces into once within 18 GX of it — no stick, angle cone or landing check,
## only `mFI_ScrollCheck` (`can_scroll(dir)`: the next acre is part of the field).
static func demo_direction(pos_gx: Vector3, facing: float, can_scroll: Callable) -> Dir:
	var local := Vector2(fposmod(pos_gx.x, BLOCK_GX), fposmod(pos_gx.z, BLOCK_GX))
	var dir_x: float = sin(facing)
	var dir_z: float = cos(facing)
	if dir_x > 0.0 and local.x >= BLOCK_GX - EDGE_GX and bool(can_scroll.call(Dir.RIGHT)):
		return Dir.RIGHT
	if dir_x < 0.0 and local.x <= EDGE_GX and bool(can_scroll.call(Dir.LEFT)):
		return Dir.LEFT
	if dir_z < 0.0 and local.y <= EDGE_GX and bool(can_scroll.call(Dir.UP)):
		return Dir.UP
	if dir_z > 0.0 and local.y >= BLOCK_GX - EDGE_GX and bool(can_scroll.call(Dir.DOWN)):
		return Dir.DOWN
	return Dir.NONE


## `mFI_ScrollCheck`: the acre `dir` of `block` is one of the town's field acres.
static func scroll_ok(block: Vector2i, dir: Dir) -> bool:
	var next: Vector2i = block
	match dir:
		Dir.RIGHT:
			next.x += 1
		Dir.LEFT:
			next.x -= 1
		Dir.UP:
			next.y -= 1
		Dir.DOWN:
			next.y += 1
	return (
		next.x >= 1 and next.x <= WorldGenerator.FG_X and next.y >= 1 and next.y <= WorldGenerator.FG_Z
	)


static func _at(dir: Dir, at_edge: bool, can_land: Callable, unable: bool) -> Dir:
	if at_edge and (unable or bool(can_land.call(dir))):
		return dir
	return Dir.NONE


## `Player_actor_CheckAbleMoveWadeBG`'s probe: 18 GX past the border, same cross position.
static func landing_probe(pos_gx: Vector3, dir: Dir) -> Vector3:
	var base: Vector2 = TownSpace.block_base(TownSpace.block_of(pos_gx))
	var out := pos_gx
	match dir:
		Dir.RIGHT:
			out.x = base.x + BLOCK_GX + EDGE_GX
		Dir.LEFT:
			out.x = base.x - EDGE_GX
		Dir.UP:
			out.z = base.y - EDGE_GX
		Dir.DOWN:
			out.z = base.y + BLOCK_GX + EDGE_GX
	return out


## `Player_actor_Culc_wade_end_pos`: 18 GX into the next acre; the cross coordinate is kept
## 18 GX clear of that acre's side edges.
static func end_pos(pos_gx: Vector3, dir: Dir) -> Vector3:
	var base: Vector2 = TownSpace.block_base(TownSpace.block_of(pos_gx))
	var out := pos_gx
	if dir == Dir.RIGHT or dir == Dir.LEFT:
		out.z = clampf(out.z, base.y + EDGE_GX, base.y + BLOCK_GX - EDGE_GX)
	else:
		out.x = clampf(out.x, base.x + EDGE_GX, base.x + BLOCK_GX - EDGE_GX)
	match dir:
		Dir.RIGHT:
			out.x = base.x + EDGE_GX + BLOCK_GX
		Dir.LEFT:
			out.x = base.x - EDGE_GX
		Dir.UP:
			out.z = base.y - EDGE_GX
		_:
			out.z = base.y + EDGE_GX + BLOCK_GX
	return out


## `get_percent_forAccelBrake(now, 0, 36, 1.2, 34.8)`.
static func percent(now: float, end: float = TICKS, accel: float = ACCEL, brake: float = BRAKE) -> float:
	if now >= end:
		return 1.0
	if now <= 0.0:
		return 0.0
	if end < accel + brake:
		return 0.0
	var step: float = 1.0 / (2.0 * end - accel - brake)
	var p: float
	if accel != 0.0:
		if now <= accel:
			return now * (step * now) / accel
		p = step * accel
	else:
		p = 0.0
	if now <= end - brake:
		return p + step * 2.0 * (now - accel)
	p += 2.0 * step * (end - accel - brake)
	if brake != 0.0:
		p += step * brake
		var diff: float = end - now
		p -= step * diff * diff / brake
	return p
