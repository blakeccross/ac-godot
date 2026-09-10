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
const GAME_FPS := 30.0

## `aINS_setupActor`: life_time 216000 frames (2 game-hours), alpha0 255, bg_range 12.
const LIFE_TIME_FRAMES := 216000
const BG_RANGE_DEFAULT := 12.0
## `aINS_MAX_STRESS_DIST` = 3 units ; `mFI_UNIT_BASE_SIZE_F` = 20 GX.
const UNIT_GX := 20.0
const MAX_STRESS_DIST_GX := 3.0 * UNIT_GX
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
	## Player planar move this 30 Hz frame, GX (`world - last_world_position`).
	var player_move_gx: float = 0.0
	var player_dashing: bool = false
	var player_yaw: float = 0.0
	var player_swung_tool: bool = false
	var player_swung_net: bool = false
	var net_swing_origin: Vector3 = Vector3.INF
	var net_swing_dir: Vector3 = Vector3.ZERO
	var net_swing_active: bool = false
	## Cell the player just acted on (shovel / axe / tree shake).
	var player_action_cell: Vector2i = Vector2i(-1, -1)
	var player_action: int = 0  ## aINS_PL_ACT_*
	## Optional BG probe (Phase 3). Callable(pos_gx: Vector3) -> Dictionary.
	var bg: Callable = Callable()

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
var block: Vector2i = Vector2i(-1, -1)

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
var _step_acc: float = 0.0


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


func in_net_volume(origin_m: Vector3, direction: Vector3, length_m: float, radius_m: float) -> bool:
	## `Player_actor_Item_CheckLocalCapture_forNet`: capsule ahead of the swing.
	var p: Vector3 = position
	var to: Vector3 = p - origin_m
	var along: float = to.dot(direction)
	if along < 0.0 or along > length_m:
		return false
	var closest: Vector3 = origin_m + direction * along
	return Vector2(closest.x - p.x, closest.z - p.z).length() <= radius_m


func net_catch_range_gx(player_yaw: float, player_faces_toward: float) -> float:
	## `aINS_get_catch_range`. `player_faces_toward` = yaw from player to this insect.
	match type:
		0, 1:  ## common / yellow butterfly
			return 24.0
		4, 5, 6, 7, 8, 19, 20, 21, 22, 23, 29, 30, 31:  ## cicadas, bee, beetles
			return _angular_catch(player_yaw, player_faces_toward)
		28:  ## cockroach only once it has stopped (`flag == 4`)
			return _angular_catch(player_yaw, player_faces_toward) if flag == 4 else 8.0
		_:
			return 8.0


func _angular_catch(player_yaw: float, _to_insect: float) -> float:
	## `aINS_get_catch_range_sub`: 24 GX if the player faces within 90° of the
	## insect's own yaw, else 0.
	if absf(wrapf(rot.y - player_yaw, -PI, PI)) > PI * 0.5:
		return 0.0
	return 24.0


# ---- 30 Hz fixed stepper -------------------------------------------------

func tick(delta: float, sense: Sense) -> void:
	## Standalone / test driver. `BugField` calls `frame()` directly at 30 Hz.
	if finished:
		return
	_step_acc += delta
	var budget: int = 8
	while _step_acc >= 1.0 / GAME_FPS and budget > 0:
		_step_acc -= 1.0 / GAME_FPS
		budget -= 1
		frame(sense)
		if finished:
			return


func frame(sense: Sense) -> void:
	## `aINS_actor_move` body for one slot (already gated on exist + not-culled).
	if finished:
		return
	## move_proc (default `aINS_position_move`).
	if move_proc.is_valid():
		move_proc.call(self)
	else:
		_position_move()
	## aINS_set_player_info handled implicitly (Sense carries player pos).
	## aINS_BGcheck — Phase 3.
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


# ---- aINS_position_move ------------------------------------------------

func _position_move() -> void:
	last_pos = pos
	speed = BugProgram.chase_f(speed, target_speed, speed_step * 0.5)
	pos_speed.x = speed * sin(angle_y)
	pos_speed.z = speed * cos(angle_y)
	if not (type in LEVEL_Y_TYPES):
		pos_speed.y = BugProgram.chase_f(pos_speed.y, max_velocity_y, gravity * 0.5)
	pos += pos_speed


# ---- aINS_calc_patience / stress -------------------------------------

func stress_radius_gx() -> float:
	var bias: float = CATCH_ME_GX[type] if type >= 0 and type < CATCH_ME_GX.size() else 0.0
	return MAX_STRESS_DIST_GX + bias


func _calc_stress(sense: Sense) -> float:
	if not sense.has_player():
		return 0.0
	var player_gx: Vector3 = sense.player_position / GX_M
	var d: float = pos.distance_to(player_gx)
	var min_dist: float = stress_radius_gx()
	if d >= min_dist:
		return 0.0
	var tmp0: float = maxf(d - UNIT_GX, 0.0)
	var idx: int = int((min_dist - UNIT_GX - tmp0) / 20.0)
	idx = clampi(idx, 0, STRESS_CALC_TABLE.size() - 1)
	## `calc_stress = |player frame move| * calc_table[idx]`.
	var move: float = _player_frame_move_gx(sense)
	return move * STRESS_CALC_TABLE[idx]


var _last_player_gx: Vector3 = Vector3.INF


func _player_frame_move_gx(sense: Sense) -> float:
	var observed: float = 0.0
	if _last_player_gx != Vector3.INF:
		observed = Vector2(
			sense.player_position.x / GX_M - _last_player_gx.x,
			sense.player_position.z / GX_M - _last_player_gx.z
		).length()
	if observed <= 0.0 and sense.player_move_gx > 0.0:
		observed = sense.player_move_gx
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
