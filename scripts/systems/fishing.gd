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
const CAST_SECONDS := 50.0 / DecompTime.TICK_HZ
const CAST_TICKS := 50
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
## `aUKI_set_proc_cast`: `cast_timer = 40`, counted down only once the bobber is floating.
## Until it runs out no fish can see the bobber (`aGTT_search_Uki`) or start nibbling.
const SETTLE_TICKS := 40
## `aUKI_set_proc_wait` / `_touch`: `frame_timer = 12`. Pressing A with nothing on the hook
## stops the bobber and reels it in once this runs out, so a fish that commits in the
## meantime is still caught.
const EMPTY_REEL_TICKS := 12
## `aUKI_set_proc_bite`'s `timer[size] * 2`: how long `vib_rod` fights a hooked fish before
## `fly_rod` lifts it out. Trash is a flat 26 ticks.
const FIGHT_FRAMES: Array[int] = [26, 39, 39, 39, 52, 65, 78, 78]
const FIGHT_TRASH_TICKS := 26
## `aUKI_movement`: within 130 GX of the player the bobber drifts with the current at
## `chase_f(speed, 0.45, 0.1)` (half that while a fish is nibbling); past it, it is towed
## back toward the player at 0.8. GX per frame, moved `0.5 *` that a tick.
const DRIFT_RADIUS_GX := 130.0
const DRIFT_SPEED_GX := 0.45
const DRIFT_TOUCH_SPEED_GX := 0.225
const DRIFT_ACCEL_GX := 0.1
const TOW_SPEED_GX := 0.8
## `aUKI_BGcheck`: the bobber keeps 12 GX off the bank while settling, then `range` eases
## out to 40 GX at 0.05 a tick.
const BANK_RANGE_START_GX := 12.0
const BANK_RANGE_GX := 40.0
const BANK_RANGE_STEP_GX := 0.05

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
## `air_rod`: the cast found no water, so `ready_rod` hands over to `NOT_SAO_SWING1` at the
## frame it checked (10) and the swing finishes empty.
const REEL_AIR := &"ply_1_not_sao_swing1"

## `putaway_rod`, which `notice_rod` requests once the catch report is dismissed.
const PUTAWAY := &"ply_1_putaway_t1"
## `Player_actor_Movement_Notice_rod` turns to `shape_info.rotation.y == 0`, which in a fixed
## 3/4 acre is square-on to the screen. Our follow camera sits on +Z and yaw 0 faces +Z, so
## the original's target angle already means "look at the camera".
const SHOW_YAW := 0.0
## Turned to with `PlayerLocomotion.ease_turn`, once per tick.
## `main_notice->timer < 42.0f`: the pose is held this long before the catch is announced,
## whatever the clip does. Mover frames, so 60 Hz.
const SHOW_HOLD_SECONDS := 42.0 / DecompTime.TICK_HZ


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
	## `mSM_CHECK_LAST_FISH_GET`: this catch is the one species the record was missing.
	## The report becomes 0x1349 (naming the fish), then 0x134A over a `YATTA2`.
	var completes_record: bool = false

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
	## `already_collected`: follow the report with 0x134A and `YATTA2`.
	var completes_record: bool = false
	## 30 fps frame the clip starts from. `air_rod` picks up `NOT_SAO_SWING1` where
	## `SAO_SWING1` left off rather than from the top.
	var start_frame: float = 0.0

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


## `aGYO_get_uki_type` — the golden rod widens every fish's search cone and lengthens
## every bite window. `golden_fishing_rod` (`Now_Private->equipment == ITM_GOLDEN_ROD`).
const GOLDEN_ROD_IDS: Array[StringName] = [&"golden_fishing_rod", &"golden_rod"]

static var _state: State = State.IDLE
static var _anchor: Vector3 = Vector3.ZERO
static var _actor: Node3D = null
static var _bobber: Node3D = null
static var _golden_rod: bool = false
static var _inventory: Inventory = null
static var _cast_ticks: int = 0
static var _dip: float = 0.0
static var _splash_pending: bool = false
static var _nibbles: int = 0
static var _reel: Array[ReelBeat] = []
static var _steps := FrameStepper.new()
## `cast_timer`: ticks left before fish may notice the bobber.
static var _settle: int = 0
## `uki->proc == aUKI_PROC_TOUCH` (`gyo_status == 2`): a fish has started nibbling, so no
## other fish may start and the nibbling one may now commit.
static var _touching: bool = false
## `uki->command == 6`: A was pressed and the line is coming in.
static var _reeling: bool = false
## `frame_timer` while reeling: ticks until the bobber comes up.
static var _reel_ticks: int = 0
## The shadow that has the bobber (`uki->child_actor`) and how long it fights once struck.
static var _hooked: FishShadow = null
static var _fight_ticks: int = 0
static var _drift_speed: float = 0.0
static var _bank_range: float = BANK_RANGE_START_GX
static var _ctx: InteractionContext = null
static var _last: Outcome = null
## Set by an `air_rod` swing: the rest of the cast swing is cut and the beat takes over.
static var _cut_swing: bool = false


static func is_active() -> bool:
	return _state != State.IDLE


static func state() -> State:
	return _state


## A was pressed and the line has not come up yet. The player holds its pose until this
## clears, then plays whatever `take_reel_beats` hands it.
static func is_reeling() -> bool:
	return _reeling and is_active()


## What the last reel-in brought up. Null until one has resolved.
static func last_outcome() -> Outcome:
	return _last


## Where the bobber is: the landing spot, and then wherever the current has carried it. The
## leash measures from here, so a headless session with no scene still drops the line when
## the caster walks off.
static func anchor() -> Vector3:
	return _anchor


## 0–1 through the cast parabola. 1.0 once the bobber has landed.
static func cast_progress() -> float:
	if _state == State.IDLE:
		return 0.0
	if _state != State.CAST:
		return 1.0
	return clampf(float(_cast_ticks) / float(CAST_TICKS), 0.0, 1.0)


## How far under the surface a nibble is currently pulling the bobber, 0–1.
static func dip() -> float:
	if _state == State.BITE:
		return 1.0
	if _dip <= 0.0:
		return 0.0
	return clampf(_dip / DIP_SECONDS, 0.0, 1.0)


static func nibble_count() -> int:
	return _nibbles


## Verb offered while a line is out. No player animation: the strike has to land on the
## tick the button is pressed. Nothing is offered while the bobber is still in the air
## (the player is still in `cast_rod`) or once the line is already coming in.
static func field_action() -> Interaction:
	if not is_active() or _state == State.CAST or _reeling:
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
	_end()
	_state = State.CAST
	_actor = actor
	_ctx = ctx
	_last = null
	_settle = SETTLE_TICKS
	_inventory = ctx.inventory
	_golden_rod = ctx.inventory != null and ctx.inventory.equipment_id in GOLDEN_ROD_IDS
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
	if not _reeling and _actor.global_position.distance_to(_anchor) > LEASH_METERS:
		Game.post_notice("Your line went slack.")
		_end(school)
		return
	_dip = maxf(_dip - delta, 0.0)
	_steps.add(delta)
	while is_active() and _steps.next():
		_step(school)


## Fills in the bobber half of a sense snapshot. The caller adds the player half.
static func fill_sense(sense: FishShadow.Sense) -> void:
	if not is_active():
		return
	sense.bobber_position = _anchor
	sense.bobber_splashed = _splash_pending
	## `cast_timer == 0`, and not while the line is coming in.
	sense.bobber_settled = _state != State.CAST and _settle <= 0
	## `gyo_status`: 1 while nothing has it, 2 once a fish is nibbling.
	sense.accepts_nibble = _state == State.FLOAT and not _touching
	sense.accepts_bite = _state == State.FLOAT and _touching
	sense.rod = FishSize.ROD_GOLDEN if _golden_rod else FishSize.ROD_NORMAL
	sense.has_pocket_space = _inventory == null or _inventory.has_space(1)


## `Player_actor_request_proc_index_fromRelax_rod`: A sets the bobber's command to 6. What
## comes up is decided a few ticks later by the bobber, not on the press — a hooked fish is
## fought for `FIGHT_FRAMES`, and an empty press still lands a fish that commits within the
## next `EMPTY_REEL_TICKS`. Returns false when there is nothing to reel.
static func hook(ctx: InteractionContext, school: FishSchool = null) -> bool:
	if not is_active() or _state == State.CAST or _reeling:
		return false
	_reeling = true
	_last = null
	if ctx != null:
		_ctx = ctx
		_inventory = ctx.inventory
	if _state == State.BITE:
		_strike()
	else:
		_reel_ticks = EMPTY_REEL_TICKS
	## A test or a paused world may not tick again; resolve straight away if the bobber
	## would have come up with no ticks to spare.
	if school == null and _state != State.BITE:
		_reel_empty(school)
	return true


## What the reel-in looks like for an outcome: `fly_rod` swings the catch up out of the
## water and `notice_rod` holds it up to the camera. A fish on the end gets both even when
## pockets are full — you see the catch before it is refused. An empty line is the single
## `collect_rod` beat, with nothing to show off. `vib_rod`'s pull (`REEL_PULL`) is not a beat:
## it plays for as long as the fight lasts, while `is_reeling` holds.
static func reel_beats(out: Outcome) -> Array[ReelBeat]:
	if out != null and out.fish != null:
		var show := ReelBeat.new(
			REEL_SHOW, ROD_LAND, true, SHOW_HOLD_SECONDS, out.catch_msg, out.fish, out.pockets_full
		)
		show.completes_record = out.completes_record
		return [ReelBeat.new(REEL_LAND, ROD_LAND), show]
	return [ReelBeat.new(REEL_EMPTY, ROD_EMPTY)]


## `air_rod`: A with nothing but land (or a far bank) 100 GX out. The swing goes over into
## `NOT_SAO_SWING1` from frame 10 and the bobber flies out and straight back; no session.
static func air_cast() -> void:
	if is_active():
		return
	var beat := ReelBeat.new(REEL_AIR, ROD_EMPTY)
	beat.start_frame = CAST_RELEASE_FRAME
	_reel = [beat]
	_cut_swing = true


## True once after `air_cast`: the player drops the tail of the cast swing.
static func take_cut_swing() -> bool:
	var cut: bool = _cut_swing
	_cut_swing = false
	return cut


## Drained by the player once the line is in. Empty unless a reel just resolved.
static func take_reel_beats() -> Array[ReelBeat]:
	var beats: Array[ReelBeat] = _reel
	_reel = []
	return beats


static func cancel(school: FishSchool = null) -> void:
	if not is_active():
		return
	_end(school)


static func reset(school: FishSchool = null) -> void:
	_end(school)
	_last = null
	_cut_swing = false


# --- one bobber tick ---------------------------------------------------------------------


static func _step(school: FishSchool) -> void:
	match _state:
		State.CAST:
			_cast_ticks += 1
			if _cast_ticks >= CAST_TICKS:
				_land()
		State.FLOAT:
			_float(school)
		State.BITE:
			_bite(school)


## `aUKI_cast`: the tick the bobber touches water. `hit_water_flag` is up for this tick only.
static func _land() -> void:
	_state = State.FLOAT
	_splash_pending = true
	_bank_range = BANK_RANGE_START_GX
	if _bobber != null and is_instance_valid(_bobber):
		PlayerSe.bobber_splash(_bobber)
	elif _actor != null and is_instance_valid(_actor):
		PlayerSe.bobber_splash(_actor)


## `aUKI_wait` / `aUKI_touch`: float, drift, and wait for a fish or the player.
static func _float(school: FishSchool) -> void:
	_splash_pending = false
	if _settle > 0:
		_settle -= 1
	var toucher: FishShadow = null
	var biter: FishShadow = null
	if school != null:
		for shadow: FishShadow in school.shadows:
			if shadow.nibbled:
				_nibbles += 1
				_dip = DIP_SECONDS
			if shadow.finished:
				continue
			if shadow.action == FishShadow.Action.TOUCH:
				toucher = shadow
			elif shadow.action == FishShadow.Action.BITE:
				biter = shadow
	if biter != null:
		## `gyo_command == 2`: `aUKI_set_proc_bite`.
		_state = State.BITE
		_hooked = biter
		_fight_ticks = FIGHT_TRASH_TICKS if biter.fish != null and biter.fish.is_trash else FIGHT_FRAMES[int(biter.size)] * 2
		if _reeling:
			_strike()
		return
	if not _touching and toucher != null and _settle <= 0:
		## `aUKI_set_proc_touch`: `frame_timer = 12` again, even mid-reel.
		_touching = true
		_reel_ticks = EMPTY_REEL_TICKS
	if _reeling:
		## `aUKI_clear_spd`: the bobber stops dead while the line tightens.
		_drift_speed = 0.0
		_reel_ticks -= 1
		if _reel_ticks <= 0:
			_reel_empty(school)
		return
	_drift(school, toucher != null)


## `aUKI_bite`: the fish has it. It holds on for its own `aGYO_bite_time`; if that runs out
## the bobber pops back up and floats on with the line still out.
static func _bite(school: FishSchool) -> void:
	if _hooked == null or _hooked.finished or not _hooked.is_hooked():
		_hooked = null
		## `aUKI_set_proc_wait`: `gyo_status = 1`, ready for the next fish.
		_state = State.FLOAT
		_touching = false
		_reel_ticks = EMPTY_REEL_TICKS
		return
	if not _reeling:
		return
	_reel_ticks -= 1
	if _reel_ticks <= 0:
		_reel_catch(school)


## `gyo_status = 4`: struck while the fish had it. It stays on until the fight is over.
static func _strike() -> void:
	_reel_ticks = _fight_ticks
	if _hooked != null:
		_hooked.hook()


static func _drift(school: FishSchool, nibbling: bool) -> void:
	if _settle <= 0:
		_bank_range = move_toward(_bank_range, BANK_RANGE_GX, BANK_RANGE_STEP_GX)
	var to_player := Vector2(_actor.global_position.x - _anchor.x, _actor.global_position.z - _anchor.z)
	var dir: float = 0.0
	if to_player.length() < DRIFT_RADIUS_GX * FieldCatalog.GX_TO_METERS:
		var target: float = DRIFT_TOUCH_SPEED_GX if nibbling else DRIFT_SPEED_GX
		_drift_speed = move_toward(_drift_speed, target, DRIFT_ACCEL_GX)
		var flow: Vector2 = school.water_flow(_anchor) if school != null else Vector2.ZERO
		dir = FishShadow.flow_angle(flow)
	else:
		_drift_speed = TOW_SPEED_GX
		dir = atan2(to_player.x, to_player.y)
	var ahead := Vector3(sin(dir), 0.0, cos(dir))
	var step: float = _drift_speed * FishShadow.MOVE_PER_TICK * FieldCatalog.GX_TO_METERS
	var next: Vector3 = _anchor + ahead * step
	## `mCoBG_BgCheckControll` with `range`: the bobber stops that far short of the bank.
	if school != null and not school.is_water(next + ahead * _bank_range * FieldCatalog.GX_TO_METERS):
		return
	_anchor = next


static func _reel_empty(school: FishSchool) -> void:
	var out := Outcome.new()
	out.too_early = true
	_finish(out, school)


## `aUKI_hit` with `gyo_status == 5`: the fish comes up with the line.
static func _reel_catch(school: FishSchool) -> void:
	var out := Outcome.new()
	var shadow: FishShadow = _hooked
	var fish: FishData = shadow.fish if shadow != null else null
	if fish == null:
		out.escaped = true
		_finish(out, school)
		return
	out.fish = fish
	## `setup_main_Notice_rod`: pockets first, then the record check, then the record —
	## whether or not the fish fit.
	out.completes_record = completes_record(fish)
	out.catch_msg = MuseumDisplay.FISH_ALREADY_MSG if out.completes_record else fish.catch_msg
	var inventory: Inventory = _inventory
	if inventory == null or not inventory.has_space_for(fish, 1) or inventory.add(fish, 1) != 0:
		## `notice_rod` → `release_creature`: shown, then thrown back.
		out.pockets_full = true
	if Game != null and Game.species_log != null:
		## `mSM_COLLECT_FISH_SET`. `Inventory.add` already did it for a banked fish.
		Game.species_log.record(fish.id)
	shadow.reel_in()
	if fish.is_trash:
		## `aGTT_comeback` → `aGTT_kage_make_actor(gyo, 1)`: junk leaves a fish's shadow
		## swimming off as it comes up — the one that was really nibbling.
		shadow.puffed = true
	_finish(out, school)


## `mSM_CHECK_LAST_FISH_GET`: every other fish is on the catch record and this one is not.
## Not "already in the museum" — it is true exactly once, for the catch that completes it.
static func completes_record(fish: FishData) -> bool:
	if fish == null or fish.is_trash or Game == null or Game.species_log == null:
		return false
	var log: SpeciesLog = Game.species_log
	if log.has(fish.id):
		return false
	var total: int = log.page_total(&"fish")
	return total > 0 and log.page_count(&"fish") == total - 1


static func _finish(out: Outcome, school: FishSchool) -> void:
	if _bobber != null and is_instance_valid(_bobber):
		PlayerSe.line_out_of_water(_bobber)
	elif _actor != null and is_instance_valid(_actor):
		PlayerSe.line_out_of_water(_actor)
	_end(school)
	_last = out
	## `_end` clears the queue, so the beats go in after it.
	_reel = reel_beats(out)


static func _end(school: FishSchool = null) -> void:
	## Only a fish still fighting is let go; one being lifted out (`COMEBACK`) stays pinned
	## until it is gone, and a real fish leaves no puff.
	var holder: FishShadow = _hooked
	if school != null and holder == null:
		holder = school.hooked_shadow()
	if holder != null and not holder.finished and holder.action == FishShadow.Action.BITE:
		holder.release()
	_state = State.IDLE
	_anchor = Vector3.ZERO
	_actor = null
	_ctx = null
	_cast_ticks = 0
	_dip = 0.0
	_nibbles = 0
	_splash_pending = false
	_golden_rod = false
	_inventory = null
	_settle = 0
	_touching = false
	_reeling = false
	_reel_ticks = 0
	_hooked = null
	_fight_ticks = 0
	_drift_speed = 0.0
	_bank_range = BANK_RANGE_START_GX
	_steps.reset()
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
