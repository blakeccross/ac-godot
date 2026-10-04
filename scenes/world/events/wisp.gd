extends EventNpc

## The Wisp (`ac_ev_ghost`, `SP_NPC_EV_GHOST`, skeleton `gst_1`). He starts out unseen
## (alpha 0) where the event put him. Within 200 GX he calls out "Excuse me…"; once the
## player is within 80 GX he shows himself and asks for his spirits. Walking more than
## 220 GX off before that gets "Not that way!" and he waits for them to come back within
## 200. Found, he wanders about half-seen (alpha 140, 80 while moving, 190 while talking) and
## can be spoken to. After his wish, or when 4:00 comes while the player is in his acre
## ("It's 4 o'clock!"), he spins, shrinks and fades away (`aEGH_byebye`).

enum Think { HIDDEN, CALLING, WAITING, FOUND, LEAVING }

## `talk_distance`s, in GX.
const NEAR_HAILS := 200.0
const NEAR_FINDS := 80.0
const TOO_FAR := 220.0
const ALPHA_SEEN := 140
const ALPHA_MOVING := 80
const ALPHA_TALKING := 190
const WANDER_RADIUS := 4
const WANDER_PAUSE := Vector2(3.0, 7.0)
## `aEGH_byebye`: spin speed builds by 60 a frame to 30000, the scale shrinks after 48
## frames and the fade starts after 43.
const SPIN_START := -1000.0
const SPIN_STEP := 60.0
const SPIN_MAX := 30000.0
const SHRINK_DELAY := 48
const FADE_DELAY := 43
const FADE_STEP := 4

var think_state: Think = Think.HIDDEN
var state: Dictionary = {}
var alpha: float = 0.0
var _home_cell: Vector2i
var _pause: float = 0.0
var _spin: float = SPIN_START
var _frames: int = 0
var _accum: float = 0.0


func _init() -> void:
	species = &"gst"
	display_name = "Wisp"


func setup() -> void:
	state = WispEvent.state()
	var world: World = World.find(get_tree())
	_home_cell = world.grid.world_to_cell(global_position) if world != null else Vector2i.ZERO
	if bool(state.get("found", false)):
		think_state = Think.FOUND
		alpha = ALPHA_SEEN
	_apply_alpha()


func idle_clip() -> String:
	return "npc_1_gstwait1"


func can_talk() -> bool:
	return think_state == Think.FOUND and not talking


func make_talk() -> BankTalk:
	return WispTalk.new(WispTalk.Kind.NORMAL, state, Game.inventory if Game != null else null, rng())


func _gx(m: float) -> float:
	return m / FieldCatalog.GX_TO_METERS


func think(delta: float) -> void:
	_accum += delta * DecompTime.FRAME_HZ
	while _accum >= 1.0:
		_accum -= 1.0
		_frame()
	if think_state == Think.LEAVING or talking:
		return
	if Clock.hour >= WispEvent.END_HOUR:
		_time_up()
		return
	var dist: float = _gx(player_distance())
	match think_state:
		Think.HIDDEN:
			if dist < NEAR_HAILS and can_call_out():
				_say(WispTalk.Kind.EXCUSE_ME)
				think_state = Think.CALLING
		Think.CALLING:
			if dist < NEAR_FINDS and can_call_out():
				_say(WispTalk.Kind.FOUND)
				think_state = Think.FOUND
			elif dist > TOO_FAR and can_call_out():
				_say(WispTalk.Kind.WRONG_WAY)
				think_state = Think.WAITING
		Think.WAITING:
			if dist < NEAR_HAILS:
				think_state = Think.CALLING
		Think.FOUND:
			_wander(delta)


func _say(kind: int) -> void:
	begin_talk(player_node(), WispTalk.new(kind, state, Game.inventory if Game != null else null, rng()), false)


## `aEGH_byebye_check`: found and in the player's acre, he says goodbye; otherwise he is
## simply gone.
func _time_up() -> void:
	var world: World = World.find(get_tree())
	var p: Node3D = player_node()
	var same_acre: bool = false
	if world != null and p != null:
		same_acre = VillagerWalk.block_from_cell(world.grid.world_to_cell(p.global_position)) \
			== VillagerWalk.block_from_cell(world.grid.world_to_cell(global_position))
	if think_state == Think.FOUND and same_acre and can_call_out():
		_say(WispTalk.Kind.TIME_UP)
		think_state = Think.LEAVING
		_frames = 0
	elif think_state != Think.FOUND or not same_acre:
		queue_free()


func talk_ended(script: BankTalk) -> void:
	var t := script as WispTalk
	if t != null and t.kind == WispTalk.Kind.NORMAL and bool(state.get("returned", false)):
		think_state = Think.LEAVING
		_frames = 0


func _wander(delta: float) -> void:
	_pause -= delta
	if _pause > 0.0 or is_moving():
		return
	_pause = rng().randf_range(WANDER_PAUSE.x, WANDER_PAUSE.y)
	var mgr: EventManager = EventManager.find(get_tree())
	if mgr == null:
		return
	for _i: int in 8:
		var c: Vector2i = _home_cell + Vector2i(rng().randi_range(-WANDER_RADIUS, WANDER_RADIUS),
			rng().randi_range(-WANDER_RADIUS, WANDER_RADIUS))
		if mgr.npc_can_stand(c):
			move_to(mgr.cell_position(c))
			return


## One 30 Hz frame of the see-through-ness and the goodbye spin.
func _frame() -> void:
	match think_state:
		Think.HIDDEN, Think.CALLING, Think.WAITING:
			alpha = 0.0
		Think.FOUND:
			var target: int = ALPHA_TALKING if talking else (ALPHA_MOVING if is_moving() else ALPHA_SEEN)
			alpha = move_toward(alpha, target, 1.0)
		Think.LEAVING:
			if talking:
				return
			_frames += 1
			_spin = minf(_spin + SPIN_STEP, SPIN_MAX)
			rotation.y += deg_to_rad(_spin * 360.0 / 65536.0)
			if _frames > SHRINK_DELAY:
				scale.x = maxf(scale.x - 0.004, 0.0)
				scale.z = scale.x
			if _frames > FADE_DELAY:
				alpha = maxf(alpha - FADE_STEP, 0.0)
				if alpha <= 0.0:
					queue_free()
	_apply_alpha()


## `gDPSetEnvColor(…, alpha)` on the XLU pass: every surface blended at `alpha` / 255, the
## model hidden outright at 0.
func _apply_alpha() -> void:
	var m: Node3D = model()
	if m == null:
		return
	var a: float = clampf(alpha / 255.0, 0.0, 1.0)
	m.visible = a > 0.0
	if a <= 0.0:
		return
	for node: Node in m.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i: int in mesh.mesh.get_surface_count():
			var mat := mesh.get_surface_override_material(i) as StandardMaterial3D
			if mat == null or not mat.has_meta(&"wisp"):
				var src := mesh.get_active_material(i) as StandardMaterial3D
				if src == null:
					continue
				mat = src.duplicate() as StandardMaterial3D
				mat.set_meta(&"wisp", true)
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mesh.set_surface_override_material(i, mat)
			mat.albedo_color.a = a
