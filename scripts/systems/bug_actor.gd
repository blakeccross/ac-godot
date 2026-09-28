class_name BugActor
extends RefCounted

## One live insect — the `aINS_INSECT_ACTOR` analog. `BugActor` holds the generic
## actor state (the struct's `s32_work*` / `f32_work*` / `timer` / `flag` scratch
## included) and runs the shared per-frame framework from `ac_insect_move.c_inc`
## (`aINS_position_move`, `aINS_calc_patience`, `aINS_calc_life_time`,
## `aINS_calc_alpha_time`, catch-range register, cull flagging). All species
## behaviour lives in a `BugProgram` (`scripts/systems/bugs/`) reached via
## `action_proc` each frame — this file never branches on `type`.
##
## Internally everything is GX and 30 Hz frames, exactly like the decomp.
## `position` (metres) is a view for the visual / net / spawn.

const GX_M := FieldCatalog.GX_TO_METERS

## `aINS_setupActor`: life_time 216000 frames (2 game-hours), alpha0 255, bg_range 12.
const LIFE_TIME_FRAMES := 216000
const BG_RANGE_DEFAULT := 12.0
## `mCoBG_GroundCheck`: river / pond units put the surface 20 GX over the bed.
const WATER_DEPTH_GX := 20.0
## `aINS_MAX_STRESS_DIST` = 3 units ; `mFI_UNIT_BASE_SIZE_F` = 40 GX (one field unit,
## one `WorldGrid` cell).
const UNIT_GX := 40.0
const MAX_STRESS_DIST_GX := 3.0 * UNIT_GX
## `mFI_BK_WORLDSIZE_X_F`: an acre (block) is 16 units.
const ACRE_GX := 16.0 * UNIT_GX
## `aINS_PATIENCE_STEP`.
const PATIENCE_STEP := 0.5
const PATIENCE_MAX := 100.0
## `aINS_get_stress_sub` distance→multiplier table.
const STRESS_CALC_TABLE: Array[float] = [0.3, 1.0, 2.0, 5.0, 10.0]
## `catch_ME_data[]` (`ac_insect_move.c_inc`) — per-type stress-radius bias, GX.
const CATCH_ME_GX: Array[float] = [
	0.0, 0.0, 0.0, 0.0, 10.0, 10.0, 10.0, 0.0, 10.0, 0.0,
	0.0, 0.0, 0.0, 0.0, 20.0, -20.0, -20.0, -20.0, -20.0, -20.0,
	-20.0, -20.0, 0.0, 0.0, -20.0, -20.0, -20.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	0.0,
]
## `aINS_calc_alpha_time`: fade begins under 24 frames, ±11 / frame.
const ALPHA_FADE_START := 24
const ALPHA_STEP := 11
## `aINS_cull_check`: >600 GX and in another acre → despawn.
const CULL_DIST_GX := 600.0
## `aINS_position_move`: these types never chase Y toward `max_velocity_y`
## (they hold their flight level; vertical bob is done by the program).
const LEVEL_Y_TYPES: Array[int] = [0, 1, 2, 3, 27, 39, 40]

## Kept for `MuseumInsectActor` / tests — beetle trunk-sway half-angle (`aIKB_wait`).
const BEETLE_SWAY_DEG := 4.21875
## Tree-cling facings used by the visual and MINO/KABUTO/SEMI programs.
const TREE_FACE_YAW := PI


class Sense:
	var player_position: Vector3 = Vector3.INF
	## Player planar speed as GX per 30 Hz decomp frame (`Player.insect_stress_move_gx`).
	## Stress uses the per-60 Hz-tick move (`world - last_world_position`); this is only
	## the fallback when no move is observed between ticks, halved to that unit.
	var player_move_gx: float = 0.0
	var player_dashing: bool = false
	var player_yaw: float = 0.0
	var player_swung_tool: bool = false
	## `aINS_get_stress` also reads the NPC actor list: every villager on the field (metres)
	## and how far it moved this 30 Hz frame (GX), index-aligned.
	var npc_positions: PackedVector3Array = PackedVector3Array()
	var npc_moves_gx: PackedFloat32Array = PackedFloat32Array()
	## `mPlib_Check_StopNet`: true for the one frame the player's swing stops or pulls in,
	## with `net_swing_origin` the net's position (metres).
	var net_swing_origin: Vector3 = Vector3.INF
	var net_swing_active: bool = false
	## Cell the player just acted on (shovel / axe / tree shake).
	var player_action_cell: Vector2i = Vector2i(-1, -1)
	var player_action: int = 0  ## aINS_PL_ACT_*
	## `Get_WadeEndPos_proc` while the player is crossing into another acre, else INF.
	var wade_end: Vector3 = Vector3.INF
	## `Actor_draw_actor_no_culling_check`: Callable(world_m: Vector3) -> bool, true while
	## the point is on screen. Unset → everything is off screen.
	var on_screen: Callable = Callable()
	## Optional BG probe. Callable(pos_gx: Vector3) -> Dictionary (walls, flowers, perches…).
	var bg: Callable = Callable()
	## Ground-only sampler for the per-frame `aINS_BGcheck` (`BugBg.make_ground`):
	## Callable(pos_gx) -> {ground_y, water, water_y}. Unset → no ground collision.
	var ground: Callable = Callable()
	## `play->game_frame`: play frames since the field loaded (`BugField` advances it).
	var game_frame: int = 0
	## `mPlib_Check_tree_shaken`: units whose tree the player is shaking or has just bumped
	## (the player's shake-table entries still running). Cell → true, in `grid`'s cells.
	var shaken_cells: Dictionary = {}
	var grid: WorldGrid = null
	var layout: WorldData = null

	func tree_shaken_at(world_m: Vector3) -> bool:
		if grid == null or shaken_cells.is_empty():
			return false
		return shaken_cells.has(grid.world_to_cell(world_m))

	func has_player() -> bool:
		return player_position != Vector3.INF


## `aINS_PL_ACT_*`
enum PlAct { NONE, REFLECT_AXE, REFLECT_SCOOP, DIG_SCOOP, SHAKE_TREE }


# ---- identity ------------------------------------------------------------
var bug: BugData = null
var type: int = 0
var habitat: BugData.Habitat = BugData.Habitat.FLYING
var item: int = -1

# ---- transform (GX, 30 Hz) ---------------------------------------------
var pos: Vector3 = Vector3.ZERO
var last_pos: Vector3 = Vector3.ZERO
var home: Vector3 = Vector3.ZERO
## shape_info.rotation — x pitch, y yaw, z roll (radians).
var rot: Vector3 = Vector3.ZERO
var angle_y: float = 0.0
var speed: float = 0.0
var target_speed: float = 0.0
var speed_step: float = 0.0
var gravity: float = 0.0
var max_velocity_y: float = 0.0
var pos_speed: Vector3 = Vector3.ZERO

# ---- shared scratch (struct fields the overlays reuse) ----------------
var patience: float = 0.0
var life_time: int = LIFE_TIME_FRAMES
var alpha_time: int = 0
var timer: int = 0
var continue_timer: int = 0
var flag: int = 0
var s32_work: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var f32_work: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var anime0: float = 0.0  ## `_1E0`
var anime1: float = 0.0  ## `_1E4`
var light_flag: int = 0
var alpha0: int = 255
var alpha1: int = 255
var alpha2: int = 0
var ut_x: int = -1
var ut_z: int = -1
var bg_type: int = 0
var bg_range: float = BG_RANGE_DEFAULT
var bg_height: float = 0.0
## `bg_collision_check.result` after this frame's `aINS_BGcheck`.
var bg_on_ground: bool = false
var bg_in_water: bool = false
var bg_ground_y: float = 0.0
var block: Vector2i = Vector2i(-1, -1)

# ---- aINS_set_player_info (refreshed every frame before the program) ----
var has_player_info: bool = false
## `player_distance_xz` / `player_distance_y` (player − insect) / `player_angle_y` (insect → player).
var player_distance_xz: float = 0.0
var player_distance_y: float = 0.0
var player_angle_y: float = 0.0
## Player position (GX) and `shape_info.rotation.y` (facing) for the escape headings.
var player_pos: Vector3 = Vector3.INF
var player_yaw: float = 0.0
## The play clock (`play->game_frame`) as of this frame, for inits that read it.
var game_frame: int = 0
## Cached `mFI_BkNum2WposXZ(block) + half an acre` of the spawn acre (see `BugProgram.acre_center`).
var acre_center_gx: Vector2 = Vector2.INF
## Released (`aINS_MAKE_EXIST`) inits read the player's facing; a net release is created
## before any frame, so `frame()` reruns the program init once the player is known.
var _init_waits_for_player: bool = false

# ---- flags (insect_flags) --------------------------------------------
var f_destruct: bool = false
var f_no_catch: bool = false   ## bit_1 — do not register a net catch target
var f_bit2: bool = false       ## bit_2 — terminal (let_escape); skip re-scare
var f_scared: bool = false     ## bit_3 — life_time hit 0
var f_bit4: bool = true        ## bit_4 — unique-wall check enabled
var released: bool = false     ## actor_specific == 1

# ---- state machine --------------------------------------------------
var action: int = -1
var action_proc: Callable = Callable()

var finished: bool = false
var caught: bool = false
var no_cull: bool = true       ## on-camera / just spawned → not cullable yet
var drawn: bool = true         ## `actor->drawn` — MINO hides in the tree

## `insect->move_proc`. Default is `aINS_position_move`; MINO installs its own.
var move_proc: Callable = Callable()

var _prog: BugProgram = null
var _rng: RandomNumberGenerator = null
var _steps := FrameStepper.new()


# ---- construction -------------------------------------------------------

static func create(
	p_bug: BugData,
	p_habitat: BugData.Habitat,
	p_position_m: Vector3,
	rng: RandomNumberGenerator,
	p_released: bool = false
) -> BugActor:
	var a := BugActor.new()
	a.bug = p_bug
	a.type = p_bug.type_index if p_bug != null else 0
	a.habitat = p_habitat
	a._rng = rng if rng != null else RandomNumberGenerator.new()
	a.pos = p_position_m / GX_M
	a.home = a.pos
	a.last_pos = a.pos
	a.released = p_released
	## `aINS_setupActor` defaults.
	a.life_time = LIFE_TIME_FRAMES
	a.alpha0 = 255
	a.f_bit4 = true
	a.bg_range = BG_RANGE_DEFAULT
	a._prog = BugProgram.create(p_bug.program if p_bug != null else BugData.Program.CHOU)
	a._prog.actor_init(a, p_released)
	a._init_waits_for_player = p_released
	return a


# ---- views for visual / net / spawn (metres) --------------------------

var position: Vector3:
	get:
		return pos * GX_M
	set(value):
		pos = value / GX_M

var yaw: float:
	get: return rot.y
	set(value): rot.y = value

var pitch: float:
	get: return rot.x
	set(value): rot.x = value

var roll: float:
	get: return rot.z
	set(value): rot.z = value

## Legacy display hook (tree-cling Y was baked into pos.y; kept 0).
var height: float = 0.0

var alpha: float:
	get: return clampf(float(alpha0) / 255.0, 0.0, 1.0)


func pose_index() -> int:
	return _prog.pose_index(self) if _prog != null else 0


# ---- public API (Netting / BugField) --------------------------------

func catch() -> void:
	if finished:
		return
	caught = true
	finished = true
	f_destruct = true


func release() -> void:
	## `aINS_make_actor` path — hand to the program's let_escape.
	if finished:
		return
	released = true
	f_no_catch = true
	if _prog != null:
		_prog.on_release(self)


func net_catch_range_gx(player_position_m: Vector3) -> float:
	## `aINS_get_catch_range`. The facing-gated types need the player in front of them.
	match type:
		0, 1:  ## common / yellow butterfly
			return 24.0
		4, 5, 6, 7, 8, 19, 20, 21, 22, 23, 29, 30, 31:  ## cicadas, bee, beetles
			return _angular_catch(player_position_m)
		28:  ## cockroach only once it has stopped (`flag == 4`)
			return _angular_catch(player_position_m) if flag == 4 else 8.0
		_:
			return 8.0


func _angular_catch(player_position_m: Vector3) -> float:
	## `aINS_get_catch_range_sub`: 24 GX while `world.angle.y` is within 90° of
	## `player_angle_y` (the angle from the insect to the player), else 0 — a bug on a
	## trunk can only be netted from the side it faces.
	var to_player: Vector3 = player_position_m - position
	var player_angle: float = atan2(to_player.x, to_player.z)
	if absf(angle_difference(player_angle, angle_y)) > PI * 0.5:
		return 0.0
	return 24.0


## `aINS_set_catch_range`: the row this insect registers with a swinging net, or null.
func net_candidate(player_position_m: Vector3) -> NetSwing.Candidate:
	if finished or caught or f_no_catch:
		return null
	var range_gx: float = net_catch_range_gx(player_position_m)
	if is_zero_approx(range_gx):
		return null
	return NetSwing.Candidate.new(self, position, range_gx)


# ---- fixed tick stepper -------------------------------------------------

func tick(delta: float, sense: Sense) -> void:
	## Standalone / test driver. `BugField` calls `frame()` directly once per tick.
	if finished:
		return
	_steps.add(delta)
	var budget: int = 8
	while budget > 0 and _steps.next():
		budget -= 1
		frame(sense)
		if finished:
			return


func frame(sense: Sense) -> void:
	## `aINS_actor_move` body for one slot (already gated on exist + not-culled).
	if finished:
		return
	if _init_waits_for_player and sense != null and sense.has_player():
		## First frame of a released insect: rerun `*_actor_init` with the player's facing
		## available, as the decomp does at construction. Nothing has moved yet.
		_init_waits_for_player = false
		_set_player_info(sense)
		f_no_catch = false
		f_bit2 = false
		_prog.actor_init(self, true)
	## move_proc (default `aINS_position_move`).
	if move_proc.is_valid():
		move_proc.call(self)
	else:
		_position_move()
	_set_player_info(sense)
	_bg_check(sense)
	_calc_patience(sense)
	_calc_life_time()
	_calc_alpha_time()
	## mv_proc — the program state machine.
	if _prog != null:
		_prog.actor_move(self, sense)
	## aINS_set_catch_range done by BugField (needs player facing).
	xyz_move_last()


func xyz_move_last() -> void:
	last_pos = pos


## `aINS_set_player_info`: distances and angle to the player, plus the player's facing.
func _set_player_info(sense: Sense) -> void:
	if sense == null:
		return
	game_frame = sense.game_frame
	if not sense.has_player():
		has_player_info = false
		player_distance_xz = 0.0
		player_distance_y = 0.0
		player_angle_y = 0.0
		return
	has_player_info = true
	player_pos = sense.player_position / GX_M
	player_yaw = sense.player_yaw
	player_distance_xz = Vector2(player_pos.x - pos.x, player_pos.z - pos.z).length()
	player_distance_y = player_pos.y - pos.y
	player_angle_y = atan2(player_pos.x - pos.x, player_pos.z - pos.z)


# ---- aINS_BGcheck ------------------------------------------------------

## `mCoBG_BgCheckControll` ground half (`mCoBG_GroundCheck` → `mCoBG_AdjustActorY`), every
## frame after the move for any `bg_type`. Feet are `pos.y + bg_height`: a foot at or under
## the ground is lifted onto it (`on_ground`, vertical speed zeroed); a grounded insect
## whose ground drops by no more than this frame's XZ step follows it down the slope.
## Water units floor 20 GX under the surface (`water_y − 20`) and flag `is_in_water`.
## Walls stay with the programs' `sense.bg` queries.
func _bg_check(sense: Sense) -> void:
	if bg_type == 0 or sense == null or not sense.ground.is_valid():
		return
	var was_on_ground: bool = bg_on_ground
	var old_ground_y: float = bg_ground_y
	bg_on_ground = false
	bg_in_water = false
	var r: Dictionary = sense.ground.call(pos)
	var ground_y: float = float(r.get("ground_y", pos.y))
	bg_ground_y = ground_y
	var foot: float = pos.y + bg_height
	if bool(r.get("water", false)):
		var water_y: float = float(r.get("water_y", ground_y + WATER_DEPTH_GX))
		var floor_y: float = water_y - WATER_DEPTH_GX
		if floor_y >= foot:
			pos.y = floor_y - bg_height
			bg_in_water = true
			bg_on_ground = true
			pos_speed.y = 0.0
		elif water_y >= foot:
			bg_in_water = true
		return
	if ground_y >= foot:
		pos.y = ground_y - bg_height
		bg_on_ground = true
		pos_speed.y = 0.0
	elif was_on_ground and old_ground_y > ground_y:
		var step: float = Vector2(pos.x - last_pos.x, pos.z - last_pos.z).length()
		if absf(ground_y - foot) <= step:
			pos.y = ground_y - bg_height
			bg_on_ground = true
			pos_speed.y = 0.0


# ---- aINS_position_move ------------------------------------------------

func _position_move() -> void:
	last_pos = pos
	speed = BugProgram.chase_f(speed, target_speed, speed_step * 0.5)
	pos_speed.x = speed * sin(angle_y)
	pos_speed.z = speed * cos(angle_y)
	if not (type in LEVEL_Y_TYPES):
		pos_speed.y = BugProgram.chase_f(pos_speed.y, max_velocity_y, gravity * 0.5)
	## `Actor_position_move`: half the position speed per 60 Hz frame ("30fps -> 60fps").
	pos += pos_speed * 0.5


# ---- aINS_calc_patience / stress -------------------------------------

func stress_radius_gx() -> float:
	var bias: float = CATCH_ME_GX[type] if type >= 0 and type < CATCH_ME_GX.size() else 0.0
	return MAX_STRESS_DIST_GX + bias


func _calc_stress(sense: Sense) -> float:
	## `aINS_get_stress`: the largest stress any moving player / NPC actor puts on it.
	var stress: float = 0.0
	if sense.has_player():
		stress = _stress_from(sense.player_position / GX_M, _player_frame_move_gx(sense))
	for i: int in mini(sense.npc_positions.size(), sense.npc_moves_gx.size()):
		stress = maxf(stress, _stress_from(sense.npc_positions[i] / GX_M, sense.npc_moves_gx[i]))
	return stress


## `aINS_get_stress_sub` for one actor at `at_gx` that moved `move_gx` this frame.
func _stress_from(at_gx: Vector3, move_gx: float) -> float:
	var d: float = pos.distance_to(at_gx)
	var min_dist: float = stress_radius_gx()
	if d >= min_dist:
		return 0.0
	var tmp0: float = maxf(d - UNIT_GX, 0.0)
	## `(int)((min_dist - 40) - tmp0) / 20` — the table steps every 20 GX.
	var idx: int = int(min_dist - UNIT_GX - tmp0) / 20
	idx = clampi(idx, 0, STRESS_CALC_TABLE.size() - 1)
	## `calc_stress = |frame move| * calc_table[idx]`.
	return move_gx * STRESS_CALC_TABLE[idx]


var _last_player_gx: Vector3 = Vector3.INF


func _player_frame_move_gx(sense: Sense) -> float:
	var observed: float = 0.0
	if _last_player_gx != Vector3.INF:
		observed = Vector2(
			sense.player_position.x / GX_M - _last_player_gx.x,
			sense.player_position.z / GX_M - _last_player_gx.z
		).length()
	if observed <= 0.0 and sense.player_move_gx > 0.0:
		observed = sense.player_move_gx / DecompTime.TICKS_PER_FRAME
	return observed


func _calc_patience(sense: Sense) -> void:
	var stress: float = _calc_stress(sense)
	if is_zero_approx(stress):
		patience = maxf(patience - PATIENCE_STEP, 0.0)
	else:
		patience = minf(patience + stress * PATIENCE_STEP, PATIENCE_MAX)
	if sense.has_player():
		_last_player_gx = sense.player_position / GX_M


func _calc_life_time() -> void:
	if life_time > 0:
		life_time -= 1
		if life_time <= 0:
			life_time = 0
			f_scared = true


func _calc_alpha_time() -> void:
	if life_time != 0 or alpha_time <= 0:
		return
	alpha_time -= 1
	if alpha_time >= ALPHA_FADE_START:
		return
	if type == 27:  ## firefly fades its glow (alpha2) up
		alpha2 = mini(alpha2 + ALPHA_STEP, 255)
		if alpha2 >= 255:
			alpha0 = 0
			alpha1 = 0
			f_destruct = true
	else:
		alpha0 = maxi(alpha0 - ALPHA_STEP, 0)
		if alpha0 <= 0:
			f_destruct = true
	if f_destruct:
		finished = true
