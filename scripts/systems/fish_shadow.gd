class_name FishShadow
extends RefCounted

## One fish shadow. Behavioral analog of `aGYO_CTRL_ACTOR` driven by the `aGTT_*` action
## procs in `ac_gyo_test.c`: wait → swim → (sees bobber) near → touch → bite → comeback,
## with escape available from anywhere. Not an autoload, and it holds no nodes — the scene
## reads `position`, `yaw` and `anim_frame` off it. `FishSchool` owns the instances.
##
## The original's shadow is not a creature simulation: it holds station facing upstream,
## sweeps a short arc, and only becomes interesting once a bobber lands in its search cone.
## That is reproduced. `mCoBG` wall segments and waterfall handling are not: the shadow is
## kept inside its `WaterBodies.Body` by cell test instead.

enum Action { WAIT, SWIM, ESCAPE, NEAR, TOUCH, BITE, COMEBACK }

## How long the shadow stays pinned to the bobber while the catch is lifted out.
const COMEBACK_SECONDS := 0.25


## Everything a shadow needs to know about the frame that it cannot see itself. The caller
## fills this in once and every shadow reads the same snapshot.
class Sense:
	var player_position: Vector3 = Vector3.INF
	var player_dashing: bool = false
	var player_swung_tool: bool = false
	## Bobber, when a line is out. `INF` means no cast.
	var bobber_position: Vector3 = Vector3.INF
	## True on the frame the bobber lands, which scares fish it lands on top of.
	var bobber_splashed: bool = false
	## False while the bobber is still in the air (`uki->cast_timer`).
	var bobber_settled: bool = false
	## The session is willing to accept a nibble / a bite.
	var accepts_nibble: bool = false
	var accepts_bite: bool = false

	func has_bobber() -> bool:
		return bobber_position != Vector3.INF

	func has_player() -> bool:
		return player_position != Vector3.INF


var fish: FishData = null
var size: FishData.SizeClass = FishData.SizeClass.S
var position: Vector3 = Vector3.ZERO
var yaw: float = 0.0
var speed: float = 0.0
var action: Action = Action.WAIT
var body: WaterBodies.Body = null
## `grid.world_to_cell`, supplied by `FishSchool`. Without it the body test is skipped
## rather than guessed at, so a headless shadow swims freely instead of pinning to a wall.
var cell_lookup: Callable = Callable()
## Set when the shadow wants to be removed: it bolted off, or it was reeled in.
var finished: bool = false
## Set on the frame a nibble lands, so the bobber can dip once per nibble.
var nibbled: bool = false
## Set on the frame the fish commits, so the session can open the hook window.
var bit: bool = false
## Set when the shadow leaves behind an escape puff.
var puffed: bool = false

var _timer: float = 0.0
var _nibbles_left: int = FishSize.TOUCH_TRIES
var _swim_phase: float = 0.0
var _swim_kind: int = 0
var _anim_elapsed: float = 0.0
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
	shadow.yaw = shadow._upstream_yaw()
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


func tick(delta: float, sense: Sense) -> void:
	nibbled = false
	bit = false
	if finished:
		return
	_anim_elapsed += delta
	match action:
		Action.WAIT:
			_wait(delta, sense)
		Action.SWIM:
			_swim(delta, sense)
		Action.ESCAPE:
			_escape(delta, sense)
		Action.NEAR:
			_near(delta, sense)
		Action.TOUCH:
			_touch(delta, sense)
		Action.BITE:
			_bite(delta, sense)
		Action.COMEBACK:
			_comeback(delta, sense)
	_advance(delta)


## The session landed the hook: the fish rides up to the bank before it stops existing.
func reel_in() -> void:
	if finished:
		return
	_enter(Action.COMEBACK)


## The session lost it: back to open water.
func release() -> void:
	if finished:
		return
	_enter(Action.ESCAPE)


# --- actions -----------------------------------------------------------------------------


func _wait(delta: float, sense: Sense) -> void:
	## `aGTT_wait`: hold station facing upstream, drifting backwards, for 100-130 frames.
	_turn_towards(_upstream_yaw(), delta)
	_timer -= delta
	if _timer <= 0.0:
		_swim_kind = _rng.randi_range(0, 2)
		_enter(Action.SWIM)
		return
	_check_threats(sense)


func _swim(delta: float, sense: Sense) -> void:
	## `aGTT_swim`: the three `swim_flag` patterns. All three run a sine speed envelope over
	## a sweep that advances 2.5 degrees a frame, so a shadow eases out and back in.
	_swim_phase += FishSize.SWEEP_DEG_PER_FRAME * FishSize.GAME_FPS * delta
	var sweep: float = 360.0 if _swim_kind == 0 else 180.0
	speed = FishSize.cruise_speed() * sin(deg_to_rad(_swim_phase))
	if _swim_kind == 2:
		_turn_towards(_upstream_yaw(), delta)
	if _swim_phase >= sweep:
		_enter(Action.WAIT)
		return
	_check_threats(sense)


func _escape(delta: float, _sense: Sense) -> void:
	## `aGTT_escape`: bolt, ease off over 100 frames, then settle back into WAIT.
	_timer -= delta
	speed = move_toward(speed, 0.0, FishSize.gx_per_frame_to_mps(FishSize.ESCAPE_DECAY_GX) * delta * FishSize.GAME_FPS)
	if _timer <= 0.0:
		_enter(Action.WAIT)


func _near(_delta: float, sense: Sense) -> void:
	## `aGTT_near`: turn onto the bobber and close. Losing sight of it drops back to WAIT.
	if not sense.has_bobber():
		_enter(Action.WAIT)
		return
	yaw = _yaw_to(sense.bobber_position)
	var dist: float = _planar_distance(sense.bobber_position)
	if dist > FishSize.search_distance(_search_area()):
		_enter(Action.WAIT)
		return
	if dist < FishSize.touch_distance(size):
		if sense.accepts_nibble:
			_enter(Action.TOUCH)
		else:
			_enter(Action.WAIT)
		return
	_check_threats(sense)


func _touch(delta: float, sense: Sense) -> void:
	## `aGTT_touch`: the nibble loop. Back off, come in, and on each approach either commit
	## (1 in 4) or nibble again. The fifth approach always commits — this is the bobber
	## dipping two or three times before it goes under.
	if not sense.has_bobber():
		_enter(Action.ESCAPE)
		return
	_timer -= delta
	if _timer > 0.0:
		return
	yaw = _yaw_to(sense.bobber_position)
	speed = FishSize.speed(size)
	if _planar_distance(sense.bobber_position) >= FishSize.touch_distance(size):
		return
	var forced: bool = _nibbles_left <= 1
	if sense.accepts_bite and (forced or _rng.randf_range(0.0, FishSize.COMMIT_CHANCE) < 1.0):
		_enter(Action.BITE)
		return
	_nibbles_left -= 1
	nibbled = true
	## `work0 = (touch_count + RANDOM2_F(30)) * 2`, then back away at `back_speed`.
	var jitter: float = FishSize.touch_jitter_seconds()
	_timer = maxf(FishSize.touch_seconds(size) + _rng.randf_range(-jitter, jitter), 0.1)
	var back_jitter: float = FishSize.back_speed_jitter()
	speed = FishSize.back_speed(size) + _rng.randf_range(-back_jitter, back_jitter)


func _bite(delta: float, sense: Sense) -> void:
	## `aGTT_bite`: the fish owns the bobber now. It sits a body-length behind it and thrashes
	## until the hold time runs out, at which point it lets go.
	if not sense.has_bobber():
		_enter(Action.ESCAPE)
		return
	var trail: float = FishSize.hook_trail(size)
	position.x = sense.bobber_position.x + sin(yaw) * trail
	position.z = sense.bobber_position.z + cos(yaw) * trail
	speed = 0.0
	_timer -= delta
	if _timer <= 0.0:
		_enter(Action.ESCAPE)


func _comeback(delta: float, sense: Sense) -> void:
	## `aGTT_comeback`: the fish is pinned to the bobber while the rod lifts it clear.
	if sense.has_bobber():
		position.x = sense.bobber_position.x
		position.z = sense.bobber_position.z
	speed = 0.0
	_timer -= delta
	if _timer <= 0.0:
		finished = true


# --- shared checks -----------------------------------------------------------------------


func _check_threats(sense: Sense) -> void:
	if _flee_from_player(sense):
		return
	if _splashed_on(sense):
		return
	if _sees_bobber(sense):
		_enter(Action.NEAR)


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
	yaw = _yaw_to(sense.player_position) + PI
	puffed = true
	finished = true
	return true


func _splashed_on(sense: Sense) -> bool:
	## `uki->hit_water_flag && target_dist < escape_dist`: a cast that lands on a fish's head
	## sends it away instead of interesting it.
	if not sense.bobber_splashed or not sense.has_bobber():
		return false
	if _planar_distance(sense.bobber_position) >= FishSize.splash_escape_distance(size):
		return false
	yaw = _yaw_to(sense.bobber_position) + PI
	_enter(Action.ESCAPE)
	return true


func _sees_bobber(sense: Sense) -> bool:
	## `aGTT_search_Uki`: inside the species' radius *and* inside its cone. A fussy fish
	## (`search_area` 0) only notices a bobber within 3 degrees of straight ahead.
	if not sense.has_bobber() or not sense.bobber_settled or not sense.accepts_nibble:
		return false
	var area: int = _search_area()
	if _planar_distance(sense.bobber_position) >= FishSize.search_distance(area):
		return false
	var off: float = absf(wrapf(_yaw_to(sense.bobber_position) - yaw, -PI, PI))
	return off <= FishSize.search_half_angle(area)


# --- helpers -----------------------------------------------------------------------------


func _enter(next: Action) -> void:
	action = next
	match next:
		Action.WAIT:
			_timer = FishSize.wait_seconds(_rng.randf())
			speed = FishSize.gx_per_frame_to_mps(
				FishSize.DRIFT_SPEED_GX + _rng.randf_range(-1.0, 1.0) * FishSize.DRIFT_JITTER_GX
			)
		Action.SWIM:
			_swim_phase = 50.0 if _swim_kind == 0 else 0.0
			if _swim_kind == 1:
				yaw += _rng.randf_range(-PI, PI)
			speed = 0.0
		Action.ESCAPE:
			_timer = FishSize.ESCAPE_FRAMES / FishSize.GAME_FPS
			speed = FishSize.escape_speed()
		Action.NEAR:
			speed = FishSize.speed(size)
		Action.TOUCH:
			_timer = 0.0
			_nibbles_left = FishSize.TOUCH_TRIES
			speed = 0.0
		Action.BITE:
			_timer = FishSize.bite_seconds(_bite_time())
			bit = true
			speed = 0.0
		Action.COMEBACK:
			## The original ends this on uki status rather than a clock. One beat of the rod
			## lift is enough for the shadow to read as "coming with you".
			_timer = COMEBACK_SECONDS
			speed = 0.0


func _advance(delta: float) -> void:
	if is_zero_approx(speed) or is_hooked():
		return
	var step: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw)) * speed * delta
	var next: Vector3 = position + step
	if body != null and not _in_body(next):
		## `aGYO_check_wall`: turn a quarter turn off the bank rather than stopping dead.
		yaw += PI * 0.5
		return
	position = next


func _in_body(at: Vector3) -> bool:
	if body == null or body.cells.is_empty() or not cell_lookup.is_valid():
		return true
	return body.contains(_cell_of(at))


func _cell_of(at: Vector3) -> Vector2i:
	return cell_lookup.call(at) as Vector2i


func _turn_towards(target: float, delta: float) -> void:
	## `chase_angle(..., 0x100)`: 0x100 of 0x10000 is 1/256 of a turn per frame.
	var rate: float = TAU / 256.0 * FishSize.GAME_FPS * delta
	yaw = _step_angle(yaw, target, rate)


static func _step_angle(from: float, to: float, max_step: float) -> float:
	var diff: float = wrapf(to - from, -PI, PI)
	if absf(diff) <= max_step:
		return to
	return from + signf(diff) * max_step


func _yaw_to(target: Vector3) -> float:
	return atan2(target.x - position.x, target.z - position.z)


func _planar_distance(target: Vector3) -> float:
	return Vector2(target.x - position.x, target.z - position.z).length()


func _upstream_yaw() -> float:
	## `aGTT_Get_flow_angle_rv`: fish hold station facing *into* the current.
	if body == null or not body.flows:
		return yaw
	return wrapf(body.flow_yaw + PI, -PI, PI)


func _search_area() -> int:
	return fish.search_area if fish != null else 2


func _bite_time() -> int:
	return fish.bite_time if fish != null else 3
