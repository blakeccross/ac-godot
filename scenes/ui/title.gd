extends Node

## Title screen: `m_trademark` → `SCENE_TITLE_DEMO` + the `ac_animal_logo` actor.
##
## The screen is a live town: `Game.begin_title_demo` fixes the date, weather and a random
## resident, the world scene builds the generated town, and a recording (`TitleDemoInput`)
## plays the player's stick and A button for 60 s (`title_demo_move`). The logo overlay
## (`TitleLogo`) animates in over it; START or A then fades to black and offers New Game /
## Continue (the original goes straight to player select). When the recording runs out the
## screen fades, holds black, and reloads into the next of the five demos.
## The Nintendo logo stage of `m_trademark` is deliberately not reproduced.

## Black between demos: `FADE_TYPE_SELECT_END` waits `S_back_title_timer` = 120 ticks.
const END_HOLD_SEC := 1.4
const MENU_FADE_SEC := 0.6

var _demo_index: int = 0
var _demo_input: TitleDemoInput = TitleDemoInput.new()
var _steps := FrameStepper.new()
var _leaving: bool = false
var _demo_over: bool = false
var _menu_open: bool = false

@onready var _world: Node = %World
@onready var _porter: StationPorter = %Porter
@onready var _logo: CanvasLayer = %TitleLogo
@onready var _menu: CanvasLayer = %Menu
@onready var _fade: ColorRect = %Fade
@onready var _new_game: Button = %NewGameButton
@onready var _continue: Button = %ContinueButton


func _enter_tree() -> void:
	## Runs before the hosted world's `_ready`, which reads this session state.
	_demo_index = TitleDemo.next_demo_index()
	Game.begin_title_demo(_demo_index)
	## `Common_Set(transition.wipe_type, WIPE_TYPE_FADE_BLACK)`: fade in from black.
	SceneTransition.hold_black()


func _ready() -> void:
	Game.notify_title_ready()
	_logo.set_demo_index(_demo_index)
	_logo.start_selected.connect(_on_start_selected)
	_logo.start_chime.connect(_on_start_chime)
	## `banti_draw` is skipped while `mEv_IsTitleDemo()`.
	var hud: Node = _world.get_node_or_null("ClockHud")
	if hud != null:
		hud.set("visible", false)
	_continue.disabled = not Game.has_continue()
	_demo_input.setup(TitleDemo.keys_for(_demo_index))
	_place_porter()
	_bind_player()
	_arm_start_gate()


func _physics_process(delta: float) -> void:
	if _leaving or _demo_over:
		return
	_steps.add(delta)
	while not _demo_over and _steps.next():
		_demo_input.step()
		_logo.button_ok = TitleDemo.button_ok(_demo_input.frame)
		if TitleDemo.is_over(_demo_input.frame):
			_end_demo()


## `title_demo_actable`: Porter on the platform in every demo.
func _place_porter() -> void:
	var layout: WorldData = _world.get("layout") as WorldData
	var grid: WorldGrid = _world.get("grid") as WorldGrid
	if layout == null or grid == null:
		return
	var pos: Vector3 = TitleDemo.gx_to_world(layout, StationPorter.TITLE_GX)
	var y: float = FieldCollision.ground_y_at(layout, grid, pos, 0.0, false)
	if FieldCollision.has_floor(y):
		pos.y = y
	_porter.place(pos)


func _bind_player() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and TitleDemo.has_data():
		player.set("scripted_input", _demo_input)


## `aAL_wipe_end_check`: START only counts once the fade-in has finished.
func _arm_start_gate() -> void:
	_logo.can_start = false
	await SceneTransition.wait_wipe_in_start()
	await get_tree().create_timer(SceneTransition.WIPE_SEC).timeout
	_logo.can_start = true


func _on_start_chime() -> void:
	## `sAdo_SysTrgStart(0x44D)`. Silent until the audio step renders that SE.
	Audio.play_se(&"44d")


func _on_start_selected() -> void:
	if _leaving:
		return
	_leaving = true
	_release_player()
	## `mBGMPsComp_make_ps_wipe`: the title music goes out with the picture.
	Audio.play_bgm(&"")
	_menu.visible = true
	_fade.color.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_fade, "color:a", 1.0, MENU_FADE_SEC)
	await tween.finished
	_show_menu()


func _show_menu() -> void:
	_menu_open = true
	_leaving = false
	_logo.visible = false
	if _continue.disabled:
		_new_game.grab_focus()
	else:
		_continue.grab_focus()


func _end_demo() -> void:
	## `mTD_game_end_init`: `FADE_TYPE_SELECT_END` + a black wipe, then back to `trademark`
	## and the next recording.
	_demo_over = true
	_release_player()
	_logo.demo_ended = true
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	await get_tree().create_timer(END_HOLD_SEC).timeout
	Fishing.reset()
	get_tree().reload_current_scene()


func _release_player() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		player.set("scripted_input", null)


func _on_new_game_pressed() -> void:
	## Full opening, like the original: K.K. player select → Rover's train → station arrival.
	_choose(Game.start_intro_sequence)


func _on_continue_pressed() -> void:
	_choose(_continue_saved_game)


func _on_generated_town_pressed() -> void:
	## Dev skip: straight into a deterministic generated town, no intro.
	_choose(func() -> void: Game.start_new_game(WorldData.Mode.GENERATED, WorldGenerator.DEFAULT_SEED))


func _on_intro_station_pressed() -> void:
	_choose(Game.start_intro_station)


func _continue_saved_game() -> void:
	await SceneTransition.play_wipe_out(SceneTransition.Style.FADE)
	Game.continue_game()


func _choose(action: Callable) -> void:
	## One transition at a time — the wipe-out entry points are async.
	if not _menu_open or _leaving:
		return
	_leaving = true
	action.call()
