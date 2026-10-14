extends EventNpc

## K.K. Slider on Saturday night (`ac_npc_totakeke`, `SP_NPC_TOTAKEKE`, skeleton `end_1`),
## sitting in front of the station (`staffroll_start`: acre A-3, unit 7,7). He strums
## (`aNPC_ACT_ENSOU`) until spoken to; `KkTalk` decides the song; then the show
## (`aNTT_think` roll procs):
##
## 1. `roll` — 3 s of quiet with the music ducked, the player held in place.
## 2. `roll1` / `roll2` — his live version (`BGM_TOTAKEKE_LIVE0 + song`), strumming in
##    time (`3HAKU` / `4HAKU`), the staff roll's 16 pages of credits fading in and out
##    (446 frames each, `aMKBC_clip_roll_draw`) and the weather running through
##    rain, leaves, snow and petals at fixed frames of the roll.
## 3. `roll4` / `roll_end` — the song ends, the town's music and weather come back, and he
##    speaks first: the aircheck (+0x0C, handed over), pockets full (+0x0B) or "not my
##    bag" for a made-up tune (+7).

const CREDITS_SCENE := preload("res://scenes/ui/kk_credits.tscn")
## `roll2_count = 180` frames of quiet before the song.
const QUIET_SECONDS := 180.0 / DecompTime.TICK_HZ
## `aMKBC_clip_roll_draw`: one page every 446 frames.
const PAGE_SECONDS := 446.0 / DecompTime.TICK_HZ
const PAGE_COUNT := 16
## `aNTT_roll2` weather cues (frames of `roll4_count`) → kind, intensity.
const WEATHER_CUES: Array = [
	[1310, &"rain", Weather.Intensity.HEAVY], [1870, &"rain", Weather.Intensity.NONE],
	[2450, &"leaves", Weather.Intensity.HEAVY], [2970, &"leaves", Weather.Intensity.NONE],
	[3910, &"snow", Weather.Intensity.HEAVY], [4800, &"snow", Weather.Intensity.NONE],
	[5600, &"sakura", Weather.Intensity.HEAVY], [6350, &"sakura", Weather.Intensity.NONE],
]
## `ABS(player_angle_y) > 4000`: out of the front row.
const FRONT_ANGLE := 4000.0 / 65536.0 * TAU

enum Show { NONE, QUIET, SONG, END }

var show_state: Show = Show.NONE
var _show_t: float = 0.0
var _song_len: float = 0.0
var _talk_after: KkTalk
var _credits: Node
var _cue: int = 0
var _saved_weather: StringName = &""
var _saved_intensity: int = 0
var _held_player: Player


func _init() -> void:
	species = &"end"
	display_name = "K.K. Slider"
	talk_label = "Talk to K.K."


func idle_clip() -> String:
	return "npc_1_ensou_e1"


func talk_clip() -> String:
	return "npc_1_wait_e1"


func can_talk() -> bool:
	return visible and show_state == Show.NONE


func _areas() -> Array[Dictionary]:
	var show_area: Dictionary = {}
	var player_area: Dictionary = {}
	if Game != null and Game.events != null:
		show_area = Game.events.area(&"kk_slider")
		## The save area lives as long as tonight's show (`mEv_reserve_save_area`).
		var today: String = Game.events.day_key()
		if str(show_area.get("date", "")) != today:
			show_area.clear()
			show_area["date"] = today
		player_area = Game.events.area(&"kk_player")
	return [show_area, player_area]


func make_talk() -> BankTalk:
	var a: Array[Dictionary] = _areas()
	var t := KkTalk.new(a[0], a[1], Game.inventory if Game != null else null)
	t.in_front = _player_in_front()
	return t


func _player_in_front() -> bool:
	var p: Node3D = player_node()
	if p == null:
		return true
	var to: Vector3 = p.global_position - global_position
	return absf(angle_difference(home_yaw, atan2(to.x, to.z))) <= FRONT_ANGLE


func talk_ended(script: BankTalk) -> void:
	super.talk_ended(script)
	if script != null and script.has_meta("give"):
		## `aNTT_talk_give`: the aircheck changes hands (already in the pockets).
		var p: Node3D = player_node()
		if p != null:
			HandOver.npc_gives_to_player(self, p, script.get_meta("give"))
		return
	var kk := script as KkTalk
	if kk == null:
		return
	if kk.wants_show():
		_talk_after = kk
		_start_show(kk.song)


## --- The show ------------------------------------------------------------------------------


func _start_show(song: int) -> void:
	show_state = Show.QUIET
	_show_t = 0.0
	_cue = 0
	_held_player = player_node() as Player
	if _held_player != null:
		_held_player.set_busy(true)
	EventManager.demo_bgm = &"_quiet"
	Audio.stop_bgm()
	if Game != null:
		_saved_weather = Game.weather
		_saved_intensity = Game.weather_intensity
		Game.set_weather(&"clear", int(Weather.Intensity.NONE))
	var id: StringName = BgmCatalog.id_for_num(192 + song)
	var stream: AudioStream = BgmCatalog.stream_for(id) if id != &"" else null
	_song_len = stream.get_length() if stream != null else PAGE_SECONDS * PAGE_COUNT
	set_meta("song_bgm", id)
	play_clip("npc_1_ensou_e1", true)


func _physics_process(delta: float) -> void:
	if show_state == Show.NONE:
		super._physics_process(delta)
		return
	_show_t += delta
	match show_state:
		Show.QUIET:
			if _show_t >= QUIET_SECONDS:
				show_state = Show.SONG
				_show_t = 0.0
				var id: StringName = get_meta("song_bgm", &"")
				EventManager.demo_bgm = id
				if id != &"":
					Audio.play_bgm(id)
				_credits = CREDITS_SCENE.instantiate()
				get_tree().current_scene.add_child(_credits)
		Show.SONG:
			_tick_song()
			if _show_t >= maxf(_song_len, 1.0):
				_end_show()


func _tick_song() -> void:
	## Strum in time (`aMKBC_clip_sound_proc`: 3 or 4 beats a bar).
	var want: String = "npc_1_4haku_e1"
	if not current_clip().ends_with(want):
		play_clip(want, true)
	var frames: float = _show_t * DecompTime.TICK_HZ
	while _cue < WEATHER_CUES.size() and frames >= float(WEATHER_CUES[_cue][0]):
		var cue: Array = WEATHER_CUES[_cue]
		_cue += 1
		if Game != null:
			var intensity: int = int(cue[2])
			Game.set_weather(cue[1] if intensity != int(Weather.Intensity.NONE) else &"clear", intensity)
	if _credits != null and is_instance_valid(_credits):
		## The staff roll starts with the song and runs page by page over it.
		var page_t: float = _show_t
		var page: int = int(page_t / PAGE_SECONDS)
		var in_page: float = fmod(page_t, PAGE_SECONDS) * DecompTime.TICK_HZ
		_credits.call("show_page", page if page < PAGE_COUNT else -1, in_page)


func _end_show() -> void:
	show_state = Show.NONE
	if _credits != null and is_instance_valid(_credits):
		_credits.queue_free()
	_credits = null
	EventManager.demo_bgm = &""
	if Game != null:
		Game.set_weather(_saved_weather, _saved_intensity)
	var world: World = World.find(get_tree())
	if world != null:
		world.call("_play_outdoor_bgm")
	if _held_player != null and is_instance_valid(_held_player):
		_held_player.set_busy(false)
	play_clip(idle_clip(), true)
	var kk: KkTalk = _talk_after
	_talk_after = null
	if kk == null:
		return
	var n: int = kk.after_show_msg()
	if n < 0:
		return
	## `aNTT_force_talk_request`: he speaks first.
	var title: String = MinidiskCatalog.song_name(kk.song) if kk.song < MinidiskCatalog.COUNT else ""
	var fixed := BankTalk.Fixed.new(n, {
		0: kk.request_text if kk.after == KkTalk.After.MADE_UP else title, 2: title,
	})
	if kk.after == KkTalk.After.GIVE:
		fixed.set_meta("give", MinidiskCatalog.item_id(kk.song))
	begin_talk(player_node(), fixed)
