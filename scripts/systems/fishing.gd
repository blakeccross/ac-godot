class_name Fishing
extends RefCounted

## The rod session. Behavioral analog of the uki status chain in `ac_uki.h`
## (carry → ready → cast → float → vib → catch) driven by the `*_ROD` player states in
## `m_player.h`. Not an autoload: `ToolUse` starts and resolves it, `bobber.tscn` presents
## it, and `fish_shadows.tscn` ticks it.
##
## The bite is not a timer. A `FishShadow` has to find the bobber inside its species'
## search cone, nibble at it, and commit — so the bobber dips a few times before it goes
## under, and which fish you get is whichever shadow bit. `FishCatalog` is only consulted
## when a shadow spawns.

enum State { IDLE, CAST, FLOAT, BITE }

const SCENE := "res://scenes/world/bobber.tscn"
## `m_player_main_ready_rod`: the bobber lands a fixed 100 GX straight ahead of the player's
## facing. You aim by turning — there is no charge-up and no variable-length cast, so this
## is the whole of the cast's reach.
const CAST_METERS := 100.0 * FieldCatalog.GX_TO_METERS
## The same routine probes the landing spot and four corners at ±10 GX, and only casts if
## every one of them is water. Otherwise the swing goes out over land (`air_rod`).
const CAST_PROBE_METERS := 10.0 * FieldCatalog.GX_TO_METERS
## `aUKI_set_proc_cast`: `frame_timer = 50` mover frames, not doubled like the authored
## 30 Hz dwell values, so 50 is already at 60 Hz. The parabola is built to reach the landing
## point in exactly that span and `aUKI_cast` ends it the moment the bobber touches water.
const CAST_SECONDS := 50.0 / 60.0
## `Player_actor_request_proc_index_fromReady_rod` fires once the swing reaches animation
## frame 10, and `cast_rod` gives the bobber its cast command on its very first frame. So the
## line leaves the rod a third of the way through the swing, not after it — the rest of the
## swing plays out around a bobber that is already in the air.
const CAST_RELEASE_FRAME := 10.0
## How high the parabola peaks, as a fraction of the throw distance.
const CAST_ARC := 0.35
## Walking away drops the line. The original locks the player through the whole cast
## instead, which we cannot do without holding the A-button loop hostage. Has to stay clear
## of `CAST_METERS` or the line would go slack the instant the bobber landed.
const LEASH_METERS := CAST_METERS + 3.0
## How long a nibble visibly pulls the bobber under.
const DIP_SECONDS := 0.22

## Reel-in clips. The original spends a whole player state on each beat: `vib_rod` pulls
## the rod over (`TURI_HIKI1`) while the rod itself flexes, `fly_rod` swings the catch up
## out of the water (`GET_T1`), and `collect_rod` is the single empty `NOT_GET_T1` beat you
## get for reeling in nothing.
const REEL_PULL := &"ply_1_turi_hiki1"
const REEL_LAND := &"ply_1_get_t1"
const REEL_EMPTY := &"ply_1_not_get_t1"
const ROD_PULL := &"sao_sinari1"
const ROD_LAND := &"sao_get_t1"
const ROD_EMPTY := &"not_sao_swing1"
## `m_player_main_notice_rod`: `fly_rod` hands off to a state that holds the catch up on
## `GET_T2` while turning to face the camera, so you get a look at what you landed. There is
## no matching rod clip — `tol_sao_1` has no `sao_get_t2` — so the rod keeps the pose it
## finished the lift in.
const REEL_SHOW := &"ply_1_get_t2"

## `putaway_rod`, which `notice_rod` requests once the catch report is dismissed.
const PUTAWAY := &"ply_1_putaway_t1"
## `Player_actor_Movement_Notice_rod` turns to `shape_info.rotation.y == 0`, which in a fixed
## 3/4 acre is square-on to the screen. Our follow camera sits on +Z and yaw 0 faces +Z, so
## the original's target angle already means "look at the camera".
const SHOW_YAW := 0.0
## `add_calc_short_angle2(&rotation.y, 0, 1 - sqrt(0.5), 2500, 50)`, stepped once per mover
## frame by `Player_actor_Movement_Notice_rod`.
const SHOW_TURN_HZ := 60.0
const SHOW_TURN_FRACTION := 0.292893  # 1 - sqrt(0.5)
const SHOW_TURN_MAX_STEP := TAU * 2500.0 / 65536.0
const SHOW_TURN_MIN_STEP := TAU * 50.0 / 65536.0
## `main_notice->timer < 42.0f`: the pose is held this long before the catch is announced,
## whatever the clip does. Mover frames, so 60 Hz.
const SHOW_HOLD_SECONDS := 42.0 / 60.0


## Result of one hook attempt. Callers read this; the notices are posted for the HUD.
class Outcome:
	var too_early: bool = false
	var escaped: bool = false
	var pockets_full: bool = false
	var fish: FishData = null
	## `Player_actor_Get_sakana_msg_num`'s message number for this species. Carried rather
	## than posted because `notice_rod` shows the report over the show-off pose and holds the
	## pose until it is dismissed, so it belongs to that beat and not to the button press.
	var catch_msg: int = 0

	func caught() -> bool:
		return fish != null and not pockets_full


## One beat of the reel-in: a player clip and the rod clip that plays under it.
class ReelBeat:
	var player_anim: StringName = &""
	var tool_anim: StringName = &""
	## Turn to `SHOW_YAW` while the beat plays, and hold it for at least `hold` seconds even
	## if the clip runs out first. Only the `notice_rod` show-off beat does either.
	var face_camera: bool = false
	var hold: float = 0.0
	## Opened once `hold` has elapsed, with the pose held until it is dismissed.
	var catch_msg: int = 0
	## Follows the catch report when the catch could not be kept.
	var pockets_full: bool = false
	## Put in the free hand for the length of the beat. Null on an empty line.
	var fish: FishData = null

	func _init(
		p_player: StringName = &"",
		p_tool: StringName = &"",
		p_face_camera: bool = false,
		p_hold: float = 0.0,
		p_catch_msg: int = 0,
		p_fish: FishData = null,
		p_pockets_full: bool = false
	) -> void:
		player_anim = p_player
		tool_anim = p_tool
		face_camera = p_face_camera
		hold = p_hold
		catch_msg = p_catch_msg
		fish = p_fish
		pockets_full = p_pockets_full


static var _state: State = State.IDLE
static var _anchor: Vector3 = Vector3.ZERO
static var _actor: Node3D = null
static var _bobber: Node3D = null
static var _cast_elapsed: float = 0.0
static var _dip: float = 0.0
static var _splash_pending: bool = false
static var _nibbles: int = 0
static var _reel: Array[ReelBeat] = []


static func is_active() -> bool:
	return _state != State.IDLE


static func state() -> State:
	return _state


## Where the line went in. The leash measures from here, not from the bobber node, so a
## headless session with no scene still drops the line when the caster walks off.
static func anchor() -> Vector3:
	return _anchor


## 0–1 through the cast parabola. 1.0 once the bobber has landed.
static func cast_progress() -> float:
	if _state == State.IDLE:
		return 0.0
	if _state != State.CAST:
		return 1.0
	return clampf(_cast_elapsed / CAST_SECONDS, 0.0, 1.0)


## How far under the surface a nibble is currently pulling the bobber, 0–1.
static func dip() -> float:
	if _state == State.BITE:
		return 1.0
	if _dip <= 0.0:
		return 0.0
	return clampf(_dip / DIP_SECONDS, 0.0, 1.0)


static func nibble_count() -> int:
	return _nibbles


## Verb offered while a line is out. No player animation: the hook has to resolve on the
## frame the button is pressed, and `_play_action` would spend the bite window animating.
static func field_action() -> Interaction:
	if not is_active():
		return null
	var prompt: String = "Reel in!" if _state == State.BITE else "Reel in"
	return Interaction.of(Interaction.HOOK, prompt, 14)


## The field's shadows, hung off the world scene next to its `WorldGrid`.
static func school_of(ctx: InteractionContext) -> FishSchool:
	if ctx == null or ctx.world == null:
		return null
	return ctx.world.get("fish") as FishSchool


## `point` is the validated landing spot — `ToolUse.cast_point` measures it out and checks
## the water. Takes a world position rather than a cell because the reach is 100 GX, which
## does not land on a cell boundary and has nothing to do with the cell the player faces.
static func cast(ctx: InteractionContext, point: Vector3) -> bool:
	if ctx == null or is_active():
		return false
	var actor := ctx.actor as Node3D
	if actor == null:
		return false
	_state = State.CAST
	_actor = actor
	_cast_elapsed = 0.0
	_dip = 0.0
	_nibbles = 0
	_splash_pending = false
	_anchor = point
	## Catalog water is a heightfield below land and we do not model the surface plane yet,
	## so the shore height the caster stands on is the closest waterline we have.
	_anchor.y = actor.global_position.y
	_bobber = _spawn_bobber(ctx.world, _anchor)
	return true


static func tick(delta: float, school: FishSchool = null) -> void:
	if not is_active():
		return
	if _actor == null or not is_instance_valid(_actor):
		_end(school)
		return
	if _actor.global_position.distance_to(_anchor) > LEASH_METERS:
		Game.post_notice("Your line went slack.")
		_end(school)
		return
	_dip = maxf(_dip - delta, 0.0)
	if _state == State.CAST:
		_cast_elapsed += delta
		if _cast_elapsed >= CAST_SECONDS:
			_state = State.FLOAT
			## `uki->hit_water_flag`: one frame of splash, which nearby fish react to.
			_splash_pending = true
		return
	if school == null:
		return
	_observe(school)


## Fills in the bobber half of a sense snapshot. The caller adds the player half.
static func fill_sense(sense: FishShadow.Sense) -> void:
	if not is_active():
		return
	sense.bobber_position = _anchor
	sense.bobber_settled = _state != State.CAST
	sense.bobber_splashed = _splash_pending
	## A fish already has it; a second one must not start nibbling.
	sense.accepts_nibble = _state == State.FLOAT
	sense.accepts_bite = _state == State.FLOAT


## Resolves on the frame the button is pressed, then leaves the reel-in performance behind
## for the player to play. The animation cannot come first: `_play_action` awaits the clip,
## and the bite window would be gone by the time the hook landed.
static func hook(ctx: InteractionContext, school: FishSchool = null) -> Outcome:
	if not is_active():
		return Outcome.new()
	var out: Outcome = _resolve_hook(ctx, school)
	_reel = reel_beats(out)
	return out


## What the reel-in looks like for an outcome: `vib_rod` pulls the rod over, `fly_rod` swings
## the catch up out of the water, and `notice_rod` holds it up to the camera. A fish on the
## end gets all three even when pockets are full — you see the catch before it is refused.
## An empty line is the single `collect_rod` beat, with nothing to show off.
static func reel_beats(out: Outcome) -> Array[ReelBeat]:
	if out != null and out.fish != null:
		return [
			ReelBeat.new(REEL_PULL, ROD_PULL),
			ReelBeat.new(REEL_LAND, ROD_LAND),
			ReelBeat.new(
				REEL_SHOW, ROD_LAND, true, SHOW_HOLD_SECONDS, out.catch_msg, out.fish, out.pockets_full
			),
		]
	return [ReelBeat.new(REEL_EMPTY, ROD_EMPTY)]


## Drained by the player once the action has been applied. Empty unless a hook just landed.
static func take_reel_beats() -> Array[ReelBeat]:
	var beats: Array[ReelBeat] = _reel
	_reel = []
	return beats


static func _resolve_hook(ctx: InteractionContext, school: FishSchool = null) -> Outcome:
	var out := Outcome.new()
	var shadow: FishShadow = school.hooked_shadow() if school != null else null
	if _state != State.BITE or shadow == null:
		out.too_early = true
		Game.post_notice("You reel in an empty hook.")
		_end(school)
		return out
	var fish: FishData = shadow.fish
	if fish == null:
		out.escaped = true
		Game.post_notice("It got away.")
		_end(school)
		return out
	out.fish = fish
	var inventory: Inventory = ctx.inventory if ctx != null else null
	if inventory == null or not inventory.has_space_for(fish, 1) or inventory.add(fish, 1) != 0:
		out.pockets_full = true
		out.catch_msg = fish.catch_msg
		_end(school)
		return out
	shadow.reel_in()
	out.catch_msg = fish.catch_msg
	## `mSM_CHECK_LAST_FISH_GET` → shorter report once the species is already in the museum.
	if Game != null and Game.museum != null and Game.museum.has_fish_id(fish.id):
		out.catch_msg = MuseumDisplay.FISH_ALREADY_MSG
	_end(school)
	return out


static func cancel(school: FishSchool = null) -> void:
	if not is_active():
		return
	_end(school)


static func reset(school: FishSchool = null) -> void:
	_end(school)


static func _observe(school: FishSchool) -> void:
	## The shadows have already seen the splash by the time this runs — the caller builds the
	## sense snapshot before ticking them — so one frame of it is spent and it clears here.
	_splash_pending = false
	## The shadows decide; the session only reacts to what they did this frame.
	var hooked: FishShadow = school.hooked_shadow()
	if _state == State.FLOAT:
		for shadow: FishShadow in school.shadows:
			if shadow.nibbled:
				_nibbles += 1
				_dip = DIP_SECONDS
		if hooked != null:
			_state = State.BITE
		return
	if _state == State.BITE and hooked == null:
		## The fish held on for its species' `aGYO_bite_time` and let go.
		Game.post_notice("It got away.")
		_end(school)


static func _end(school: FishSchool = null) -> void:
	if school != null:
		var hooked: FishShadow = school.hooked_shadow()
		if hooked != null and not hooked.finished:
			hooked.release()
	_state = State.IDLE
	_anchor = Vector3.ZERO
	_actor = null
	_cast_elapsed = 0.0
	_dip = 0.0
	_nibbles = 0
	_splash_pending = false
	## `hook` fills this in after `_end` runs, so dropping the line never leaves a reel queued.
	_reel = []
	if _bobber != null and is_instance_valid(_bobber):
		_bobber.queue_free()
	_bobber = null


static func _spawn_bobber(world: Node, pos: Vector3) -> Node3D:
	if world == null or not ResourceLoader.exists(SCENE):
		return null
	var parent: Node = world.get_node_or_null("Effects")
	if parent == null:
		parent = world.get_node_or_null("Objects")
	if parent == null:
		return null
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null:
		return null
	var bobber := packed.instantiate() as Node3D
	if bobber == null:
		return null
	parent.add_child(bobber)
	if bobber.is_inside_tree():
		bobber.global_position = pos
	else:
		bobber.position = pos
	return bobber
