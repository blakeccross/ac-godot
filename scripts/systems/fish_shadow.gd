class_name FishShadow
extends RefCounted

## One fish shadow. Behavioral analog of `aGYO_CTRL_ACTOR` driven by the `aGTT_*` action
## procs in `ac_gyo_test.c`: wait → swim → (sees bobber) near → touch → bite → comeback,
## with escape available from wait / swim. Not an autoload, and it holds no nodes — the
## scene reads `position`, `yaw` and `anim_frame` off it. `FishSchool` owns the instances.
##
## The original's shadow is not a creature simulation: it holds station facing upstream,
## sweeps a short arc, and only becomes interesting once a bobber lands in its search cone.
## That is reproduced one mover tick (60 Hz) at a time, because every step in it is a
## per-tick `chase_f` / `DECREMENT_TIMER`. `mCoBG` wall segments and waterfall handling are
## not: the shadow is kept inside its `WaterBodies.Body` by cell test instead.
##
## Speeds are kept in the original's unit, GX per 30 fps frame, because that is what every
## table and `chase_f` step is written in. `Actor_position_move` adds `0.5 * speed` a tick,
## so a speed of 1.0 is 30 GX a second — `_advance` does that conversion and nothing else.

enum Action { WAIT, SWIM, ESCAPE, NEAR, TOUCH, BITE, COMEBACK }

## How long the shadow stays pinned to the bobber while the catch is lifted out.
const COMEBACK_SECONDS := 0.25

## `aGTT_swim_speed_check(gyo, 360/180, 5.0f, 0.5f)` / `aGTT_swim_speed_change(..., 1.0f)`:
## peak speed of each `swim_flag` pattern, GX per frame.
const SWIM_PEAK_GX: Array[float] = [0.5, 0.5, 1.0]
## Where each pattern's sweep starts and ends (`aGTT_swim_init` / the `target` argument).
const SWIM_SWEEP_FROM: Array[float] = [50.0, 0.0, 0.0]
const SWIM_SWEEP_TO: Array[float] = [360.0, 180.0, 180.0]
## `aGTT_swim_speed_change`: once the sweep passes `step` (5°), the body turns by
## `(flow_rv - heading) / (target / step)` each tick.
const SWIM_TURN_DIVISOR := 180.0 / 5.0
const SWIM_TURN_START_DEG := 5.0
## `aGTT_swim_init`: `swim_flag` 1 sets off `RANDOM2_F(180°)` from its heading and `swim_flag` 2
## picks a new heading `RANDOM2_F(90°)` away. `RANDOM2_F(n)` is `fqrand2() * n`, and
## `fqrand2` is -0.5..0.5, so both spreads are half the named angle each way.
const SWIM_SIDESTEP_SPREAD := PI
const SWIM_TURN_SPREAD := PI * 0.5
## `aGTT_chase_s_angle(gyo, swork3, 0x400)`: swim pattern 2's turn before it sets off.
const SWIM_TURN_STEP := 0x400 * MLib.S16
## `aGTT_flow_direction`'s `angl_add_table`: 0x100 a tick, 0x400 when more than 90° off.
const FLOW_TURN_SLOW := 0x100 * MLib.S16
const FLOW_TURN_FAST := 0x400 * MLib.S16
## `Actor_position_move`: `world.position += 0.5 * position_speed` per tick.
const MOVE_PER_TICK := 0.5


## Everything a shadow needs to know about the tick that it cannot see itself. The caller
## fills this in once and every shadow reads the same snapshot.
class Sense:
	var player_position: Vector3 = Vector3.INF
	var player_dashing: bool = false
	var player_swung_tool: bool = false
	## Bobber, when a line is out. `INF` means no cast.
	var bobber_position: Vector3 = Vector3.INF
	## `uki->hit_water_flag`: true on the tick the bobber lands, which scares fish it lands
	## on top of.
	var bobber_splashed: bool = false
	## False while the bobber is still in the air or settling (`uki->cast_timer != 0`).
	var bobber_settled: bool = false
	## `uki->gyo_status == 1`: the bobber is floating with nothing on it.
	var accepts_nibble: bool = false
	## `uki->gyo_status == 2`: the bobber has taken the nibbling fish's command.
	var accepts_bite: bool = false
	## `uki->status == aUKI_STATUS_COMEBACK`: the line is coming up out of the water. A fish
	## still nibbling at it is frightened off.
	var bobber_reeled: bool = false
	## `bite_check` → `gyo_flags & 1`: some shadow is already closing on / has the bobber.
	## `FishSchool` fills it in before each shadow's tick.
	var bobber_taken: bool = false
	## `aGYO_get_uki_type` — `FishSize.ROD_NORMAL` / `ROD_GOLDEN`. The golden rod widens
	## every search cone and lengthens every bite window.
	var rod: int = FishSize.ROD_NORMAL
	## `mPlib_Get_space_putin_item() >= 0` — a pocket is free, so the trash swap can happen.
	var has_pocket_space: bool = true

	func has_bobber() -> bool:
		return bobber_position != Vector3.INF

	func has_player() -> bool:
		return player_position != Vector3.INF


var fish: FishData = null
var size: FishData.SizeClass = FishData.SizeClass.S
var position: Vector3 = Vector3.ZERO
## `shape_info.rotation.y`: where the shadow's body points, and what the search cone uses.
var yaw: float = 0.0
## `world.angle.y`: where it is actually moving. Usually `yaw`; the swim patterns split
## them, so a shadow can slide sideways or keep going while its body swings round.
var heading: float = 0.0
## `actor.speed`, GX per 30 fps frame along `heading`. Negative swims tail first.
var speed: float = 0.0
var action: Action = Action.WAIT
var body: WaterBodies.Body = null
## `grid.world_to_cell`, supplied by `FishSchool`. Without it the body test is skipped
## rather than guessed at, so a headless shadow swims freely instead of pinning to a wall.
var cell_lookup: Callable = Callable()
## `mCoBG_GetWaterFlow` at a position, as a planar (x, z) vector. Supplied by `FishSchool`
## from the unit attributes; without it the body's own `flow_yaw` stands in.
var flow_lookup: Callable = Callable()
## Set when the shadow wants to be removed: it bolted off, or it was reeled in.
var finished: bool = false
## Set on the tick a nibble lands, so the bobber can dip once per nibble.
var nibbled: bool = false
## Set on the tick the fish commits and takes the bobber under.
var bit: bool = false
## Set when the shadow leaves with a `GYO_KAGE` puff (scared, or it let go of the hook).
var puffed: bool = false
## `aGTT_touch`: the 1-in-20 `gomi[]` swap. Tests that stock one exact species turn it off.
var allow_trash_swap: bool = true

## `work0`, in mover ticks.
var _timer: float = 0.0
var _rod: int = FishSize.ROD_NORMAL
var _nibbles_left: int = FishSize.TOUCH_TRIES
var _swim_phase: float = 0.0
var _swim_kind: int = 0
## `swork2` / `swork3` and `gyo_flags & 0x80` for the swim patterns.
var _swim_turn: float = 0.0
var _swim_target: float = 0.0
var _swim_turning: bool = false
## `gyo_flags & 0x40`: the escape already turned off one wall. Only the escape's own
## timeout clears it.
var _wall_turned: bool = false
## Set by `_advance` when the step would have left the water (`bg_collision_check.hit_wall`).
var _hit_wall: bool = false
## `uki->gyo_status == 4`: the player struck while the fish had it, so it stays on the hook.
var _landed: bool = false
var _anim_elapsed: float = 0.0
var _steps := FrameStepper.new()
var _rng: RandomNumberGenerator = null


static func create(
	p_fish: FishData, p_body: WaterBodies.Body, p_position: Vector3, rng: RandomNumberGenerator
) -> FishShadow:
	var shadow := FishShadow.new()
	shadow.fish = p_fish
	shadow.size = p_fish.size_class if p_fish != null else FishData.SizeClass.S
	shadow.body = p_body
	shadow.position = p_position
	shadow._rng = rng if rng != null else RandomNumberGenerator.new()
	## `aGTT_actor_init` faces the fish upstream, then drops straight into WAIT.
	shadow._set_angle(shadow._upstream_yaw())
	shadow._enter(Action.WAIT)
	return shadow


func shadow_extent() -> Vector2:
	return FishSize.shadow_size(size)


func anim_frame() -> int:
	## WHALE has a `dec_step` of 0.0, so its shadow is frozen.
	if FishSize.WHALE_IS_STILL and size == FishData.SizeClass.WHALE:
		return 0
	return FishSize.anim_frame(_anim_elapsed)


func body_blend() -> float:
	return FishSize.body_blend(anim_frame())


func is_hooked() -> bool:
	return action == Action.BITE or action == Action.COMEBACK


## Whether this shadow holds the bobber for everyone else (`gyo_flags & 2`, set by
## `aGTT_near_init` and cleared by `aGTT_wait_init`).
func is_engaged() -> bool:
	return action == Action.NEAR or action == Action.TOUCH or is_hooked()


func is_landed() -> bool:
	return _landed


## Advance by `delta` seconds, one whole mover tick at a time. `FishSchool` calls `step`
## directly so every shadow sees the others' state from the same tick; this is for a shadow
## driven on its own.
func tick(delta: float, sense: Sense) -> void:
	nibbled = false
	bit = false
	if finished:
		return
	_steps.add(delta)
	var splashed: bool = sense.bobber_splashed
	while not finished and _steps.next():
		_step(sense)
		## `hit_water_flag` is a one-tick flag; only the first tick of a batch sees it.
		sense.bobber_splashed = false
	sense.bobber_splashed = splashed


## Exactly one mover tick. The one-tick flags (`nibbled`, `bit`) are cleared first.
func step(sense: Sense) -> void:
	nibbled = false
	bit = false
	if finished:
		return
	_step(sense)


## The player struck while the fish had the bobber (`gyo_status` 4): it stays on the line
## until the session lifts it with `reel_in`.
func hook() -> void:
	if action == Action.BITE:
		_landed = true


## The session landed the hook: the fish rides up to the bank before it stops existing.
func reel_in() -> void:
	if finished:
		return
	_enter(Action.COMEBACK)


## The session lost it: the fish goes the way it does when its bite runs out.
func release() -> void:
	if finished:
		return
	_vanish()


# --- one mover tick ----------------------------------------------------------------------


func _step(sense: Sense) -> void:
	_rod = sense.rod
	_anim_elapsed += DecompTime.TICK_SEC
	## `aGYO_actor_move`: `aGYO_position_move` runs before the action proc every tick.
	_advance()
	match action:
		Action.WAIT:
			_wait(sense)
		Action.SWIM:
			_swim(sense)
		Action.ESCAPE:
			_escape(sense)
		Action.NEAR:
			_near(sense)
		Action.TOUCH:
			_touch(sense)
		Action.BITE:
			_bite(sense)
		Action.COMEBACK:
			_comeback(sense)
	_hit_wall = false


func _wait(sense: Sense) -> void:
	## `aGTT_wait`: hold station facing upstream, drifting backwards, for 200-260 ticks.
	_flow_direction()
	_timer -= 1.0
	if _timer <= 0.0:
		## `RANDOM_F(3.0f)` into thirds.
		_swim_kind = mini(int(_rng.randf() * 3.0), 2)
		_enter(Action.SWIM)
		return
	if not _flee_from_player(sense) and _search_bobber(sense):
		_enter(Action.NEAR)


func _swim(sense: Sense) -> void:
	## `aGTT_swim`: a wall sends the fish off at escape speed rather than stopping it.
	if _hit_wall:
		_turn_off_wall()
		_enter(Action.ESCAPE)
		return
	var done: bool = false
	if _swim_kind == 2 and _swim_turning:
		## `aGTT_chase_s_angle(gyo, swork3, 0x400)`: face the new heading first.
		_set_angle(_step_angle(heading, _swim_target, SWIM_TURN_STEP))
		if absf(wrapf(heading - _swim_target, -PI, PI)) < SWIM_TURN_STEP:
			_swim_turning = false
	else:
		## `chase_f(&fwork3, target, 5.0f * 0.5f)`: the sweep, and speed its sine.
		var target: float = SWIM_SWEEP_TO[_swim_kind]
		_swim_phase = move_toward(_swim_phase, target, FishSize.SWEEP_DEG_PER_FRAME)
		done = is_equal_approx(_swim_phase, target)
		if _swim_kind == 2:
			## `aGTT_swim_speed_change`: the body swings back past upstream while the fish
			## keeps sliding along the heading it picked.
			if _swim_phase > SWIM_TURN_START_DEG:
				yaw = wrapf(yaw + _swim_turn, -PI, PI)
			elif is_equal_approx(_swim_phase, SWIM_TURN_START_DEG):
				_swim_turn = wrapf(_swim_turn - heading, -PI, PI) / SWIM_TURN_DIVISOR
		speed = SWIM_PEAK_GX[_swim_kind] * sin(deg_to_rad(_swim_phase))
		if done and _swim_kind != 0:
			## Patterns 1 and 2 hand the body's facing back to the heading at the end.
			heading = yaw
	if done:
		_enter(Action.WAIT)
		return
	if not _flee_from_player(sense) and _search_bobber(sense):
		_enter(Action.NEAR)


func _escape(sense: Sense) -> void:
	## `aGTT_escape`: bolt and ease off, but a bobber in view or a dash still counts.
	if _flee_from_player(sense):
		return
	if _search_bobber(sense):
		_enter(Action.NEAR)
		return
	if _hit_wall and not _wall_turned:
		## `aGYO_check_wall`: one quarter turn off the first bank it meets.
		_turn_off_wall()
		return
	_timer -= 1.0
	if _timer <= 0.0:
		_wall_turned = false
		_enter(Action.WAIT)
		return
	speed = move_toward(speed, 0.0, FishSize.ESCAPE_DECAY_GX)


func _near(sense: Sense) -> void:
	## `aGTT_near`: turn onto the bobber and close. No threat checks here — a fish that has
	## seen the bobber ignores a dash until it is back in WAIT.
	if not sense.has_bobber():
		_enter(Action.WAIT)
		return
	_set_angle(_yaw_to(sense.bobber_position))
	var dist: float = _planar_distance(sense.bobber_position)
	if dist > FishSize.search_distance(_search_area(), _rod):
		_enter(Action.WAIT)
	elif dist < FishSize.touch_distance(size):
		if sense.accepts_nibble:
			_enter(Action.TOUCH)
		else:
			_enter(Action.WAIT)


func _touch(sense: Sense) -> void:
	## `aGTT_touch`: the nibble loop. Back off, come in, and on each approach either commit
	## (1 in 4) or nibble again. The fifth approach always commits — this is the bobber
	## dipping two or three times before it goes under.
	if not sense.has_bobber():
		_vanish()
		return
	_timer = maxf(_timer - 1.0, 0.0)
	if _timer <= 0.0:
		_set_angle(_yaw_to(sense.bobber_position))
		speed = float(FishSize.SPEED_GX[int(size)])
		if _planar_distance(sense.bobber_position) < FishSize.touch_distance(size):
			if _approach(sense):
				return
	## `uki->status == 6`: the line came up under it. `aGTT_kage_make_actor(gyo, 0)`.
	if sense.bobber_reeled:
		_vanish()


## One approach inside touch range. Returns true when the fish committed.
func _approach(sense: Sense) -> bool:
	## `(aGTT_random_check(4) && check_fall) || DECREMENT_TIMER(touch_counter) == 0`.
	## `aGTT_random_check(v)` is `RANDOM_F(v) < 1.0` — a flat 1-in-`v` chance — and a hit
	## short-circuits the counter.
	var commit: bool = _rng.randf_range(0.0, FishSize.COMMIT_CHANCE) < 1.0
	if not commit:
		_nibbles_left = maxi(_nibbles_left - 1, 0)
		commit = _nibbles_left <= 0
	if commit:
		## Nothing happens until the bobber has switched over to its touch proc
		## (`gyo_status == 2`); the fish just keeps pressing in, re-rolling every tick.
		if not sense.accepts_bite:
			return false
		## `aGTT_random_check(20)` — 1 time in 20, a committing fish is really trash. Only
		## `gyo_type` changes: the shadow keeps its size.
		if allow_trash_swap and sense.has_pocket_space and _rng.randf_range(0.0, FishSize.TRASH_CHANCE) < 1.0:
			var trash: FishData = FishCatalog.trash_for_size(size)
			if trash != null:
				fish = trash
		_enter(Action.BITE)
		return true
	nibbled = true
	## `work0 = (int)((touch_count + RANDOM2_F(30)) * 2)`, then back away at
	## `back_speed + RANDOM2_F(0.2)`.
	_timer = floorf(
		(float(FishSize.TOUCH_FRAMES[int(size)]) + _rand2(FishSize.TOUCH_JITTER_FRAMES))
		* FishSize.AUTHORED_TICK_SCALE
	)
	speed = float(FishSize.BACK_SPEED_GX[int(size)]) + _rand2(FishSize.BACK_SPEED_JITTER_GX)
	return false


func _bite(sense: Sense) -> void:
	## `aGTT_bite`: the fish owns the bobber now. It sits a body-length behind it until the
	## hold runs out, and then it is simply gone (`aGTT_kage_make_actor`) — the bobber floats
	## back up and the line stays out for the next fish.
	if not sense.has_bobber():
		_vanish()
		return
	var trail: float = FishSize.hook_trail(size)
	position.x = sense.bobber_position.x + sin(yaw) * trail
	position.z = sense.bobber_position.z + cos(yaw) * trail
	speed = 0.0
	if _landed:
		return
	_timer -= 1.0
	if _timer <= 0.0:
		_vanish()


func _comeback(sense: Sense) -> void:
	## `aGTT_comeback`: the fish is pinned to the bobber while the rod lifts it clear.
	if sense.has_bobber():
		position.x = sense.bobber_position.x
		position.z = sense.bobber_position.z
	speed = 0.0
	_timer -= 1.0
	if _timer <= 0.0:
		finished = true


# --- shared checks -----------------------------------------------------------------------


func _flee_from_player(sense: Sense) -> bool:
	## `aGTT_player_near`: only a *dashing* player or a swung tool scares fish. Walking up
	## to the bank is fine, which is why you can fish next to your own house.
	if not sense.has_player():
		return false
	var dist: float = _planar_distance(sense.player_position)
	var scared: bool = (
		(sense.player_dashing and dist < FishSize.SCARE_DASH_GX * FishSize.GX)
		or (sense.player_swung_tool and dist < FishSize.SCARE_TOOL_GX * FishSize.GX)
	)
	if not scared:
		return false
	_set_angle(_yaw_to(sense.player_position) + PI)
	_vanish()
	return true


## `aGTT_search_Uki`: the splash check and the sighting check in one. A cast that lands on
## the fish's head sends it off (and returns false); otherwise the bobber has to be settled,
## unclaimed, inside the species' radius *and* inside its cone.
func _search_bobber(sense: Sense) -> bool:
	if not sense.has_bobber():
		return false
	var dist: float = _planar_distance(sense.bobber_position)
	if sense.bobber_splashed and dist < FishSize.splash_escape_distance(size):
		_set_angle(_yaw_to(sense.bobber_position) + PI)
		_enter(Action.ESCAPE)
		return false
	if sense.bobber_taken or not sense.bobber_settled or not sense.accepts_nibble:
		return false
	var area: int = _search_area()
	if dist >= FishSize.search_distance(area, _rod):
		return false
	## `goal_angle = target_angle - shape_info.rotation.y`, strictly inside ±search_angle.
	var off: float = absf(wrapf(_yaw_to(sense.bobber_position) - yaw, -PI, PI))
	return off < FishSize.search_half_angle(area, _rod)


# --- helpers -----------------------------------------------------------------------------


func _enter(next: Action) -> void:
	action = next
	match next:
		Action.WAIT:
			## `aGTT_wait_init`: `work0 = (100 + RANDOM_F(30)) * 2`, `speed = -0.15 + RANDOM2_F(0.2)`.
			_timer = floorf(FishSize.wait_seconds(_rng.randf()) * DecompTime.TICK_HZ)
			speed = FishSize.DRIFT_SPEED_GX + _rand2(FishSize.DRIFT_JITTER_GX)
		Action.SWIM:
			_swim_phase = SWIM_SWEEP_FROM[_swim_kind]
			_swim_turn = 0.0
			_swim_turning = false
			match _swim_kind:
				1:
					## Slides off sideways; the body keeps its facing until the sweep ends.
					heading = wrapf(heading + _rand2(SWIM_SIDESTEP_SPREAD), -PI, PI)
				2:
					_swim_turning = true
					_swim_turn = _upstream_yaw()
					_swim_target = wrapf(heading + _rand2(SWIM_TURN_SPREAD), -PI, PI)
					yaw = heading
			speed = 0.0
		Action.ESCAPE:
			_timer = FishSize.ESCAPE_FRAMES
			speed = FishSize.ESCAPE_SPEED_GX
		Action.NEAR:
			speed = float(FishSize.SPEED_GX[int(size)])
		Action.TOUCH:
			_timer = 0.0
			_nibbles_left = FishSize.TOUCH_TRIES
			speed = 0.0
		Action.BITE:
			_timer = FishSize.bite_seconds(_bite_time(), _rod) * DecompTime.TICK_HZ
			_landed = false
			bit = true
			speed = 0.0
		Action.COMEBACK:
			## The original ends this on uki status rather than a clock. One beat of the rod
			## lift is enough for the shadow to read as "coming with you".
			_timer = COMEBACK_SECONDS * DecompTime.TICK_HZ
			speed = 0.0


## `aGTT_kage_make_actor(gyo, 0)`: the shadow is replaced by a fading puff and destroyed.
func _vanish() -> void:
	puffed = true
	finished = true


func _advance() -> void:
	## `Actor_position_moveF`: `0.5 * speed` GX a tick along `world.angle.y`.
	if is_zero_approx(speed) or is_hooked():
		return
	var step_gx: float = speed * MOVE_PER_TICK
	var next: Vector3 = position + Vector3(sin(heading), 0.0, cos(heading)) * step_gx * FishSize.GX
	if body != null and not _in_body(next):
		## `mCoBG_BgCheckControll` holds it at the bank and flags the wall hit.
		_hit_wall = true
		return
	position = next


## `aGYO_check_wall`: a quarter turn, towards whichever side is still water.
func _turn_off_wall() -> void:
	_wall_turned = true
	var left: float = heading + PI * 0.5
	var right: float = heading - PI * 0.5
	var probe: float = FishSize.ESCAPE_SPEED_GX * MOVE_PER_TICK * FishSize.GX * 4.0
	var left_ok: bool = _in_body(position + Vector3(sin(left), 0.0, cos(left)) * probe)
	var right_ok: bool = _in_body(position + Vector3(sin(right), 0.0, cos(right)) * probe)
	_set_angle(right if right_ok and not left_ok else left)


func _in_body(at: Vector3) -> bool:
	if body == null or body.cells.is_empty() or not cell_lookup.is_valid():
		return true
	return body.contains(cell_lookup.call(at) as Vector2i)


func _set_angle(value: float) -> void:
	## `aGTT_set_angle`: world and shape together.
	yaw = wrapf(value, -PI, PI)
	heading = yaw


func _flow_direction() -> void:
	## `aGTT_flow_direction`: `chase_angle` onto upstream, 0x100 a tick, 0x400 if more than
	## a quarter turn off.
	var target: float = _upstream_yaw()
	var off: float = absf(wrapf(heading - target, -PI, PI))
	var rate: float = FLOW_TURN_FAST if off > PI * 0.5 else FLOW_TURN_SLOW
	_set_angle(_step_angle(heading, target, rate))


static func _step_angle(from: float, to: float, max_step: float) -> float:
	var diff: float = wrapf(to - from, -PI, PI)
	if absf(diff) <= max_step:
		return to
	return from + signf(diff) * max_step


func _rand2(span: float) -> float:
	## `RANDOM2_F(span)`: `fqrand2()` is -0.5..0.5, so half the span either way.
	return (_rng.randf() - 0.5) * span


func _yaw_to(target: Vector3) -> float:
	return atan2(target.x - position.x, target.z - position.z)


func _planar_distance(target: Vector3) -> float:
	return Vector2(target.x - position.x, target.z - position.z).length()


func _upstream_yaw() -> float:
	## `aGTT_Get_flow_angle_rv`: `atans_table(flow)` turned half round. Still water has a
	## zero flow, `atans_table(0, 0)` is 0 (+Z), so a pond fish holds station facing -Z.
	var flow: Vector2 = Vector2.ZERO
	if flow_lookup.is_valid():
		flow = flow_lookup.call(position) as Vector2
	elif body != null and body.flows:
		flow = Vector2(sin(body.flow_yaw), cos(body.flow_yaw))
	return wrapf(FishShadow.flow_angle(flow) + PI, -PI, PI)


## `atans_table(flow.z, flow.x)` for a planar (x, z) flow. Zero flow reads as 0 (+Z).
static func flow_angle(flow: Vector2) -> float:
	if flow.is_zero_approx():
		return 0.0
	return atan2(flow.x, flow.y)


func _search_area() -> int:
	return fish.search_area if fish != null else 2


func _bite_time() -> int:
	return fish.bite_time if fish != null else 3
