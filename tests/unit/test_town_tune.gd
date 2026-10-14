extends GdUnitTestSuite

## `m_melody.c` / `m_mscore_ovl.c`: the town tune and its editor.


func test_pack_round_trips_the_default_tune() -> void:
	var notes := TownTune.default_notes()
	assert_int(notes.size()).is_equal(16)
	assert_array(Array(TownTune.unpack(TownTune.pack(notes)))).is_equal(Array(notes))
	## First step in the top nibble.
	assert_int((TownTune.pack(notes) >> 60) & 0xF).is_equal(7)


func test_steps_cycle_rest_tie_notes_random() -> void:
	## Down from rest is blocked; up from random is blocked.
	assert_int(TownTune.step_down(TownTune.REST)).is_equal(TownTune.REST)
	assert_int(TownTune.step_up(TownTune.RANDOM)).is_equal(TownTune.RANDOM)
	assert_int(TownTune.step_up(TownTune.REST)).is_equal(TownTune.TIE)
	assert_int(TownTune.step_up(TownTune.TIE)).is_equal(0)
	assert_int(TownTune.step_down(0)).is_equal(TownTune.TIE)
	assert_int(TownTune.step_up(12)).is_equal(TownTune.RANDOM)
	assert_str(String(TownTune.note_se(TownTune.REST))).is_empty()
	assert_str(String(TownTune.note_se(0))).is_equal("note_g_low")


func test_sanitize_rejects_bad_saves() -> void:
	assert_array(Array(TownTune.sanitize(null))).is_equal(Array(TownTune.default_notes()))
	assert_array(Array(TownTune.sanitize([1, 2]))).is_equal(Array(TownTune.default_notes()))
	var ok: Array = []
	for i: int in 16:
		ok.append(i)
	assert_array(Array(TownTune.sanitize(ok))).is_equal(ok)


func test_editor_changes_steps_and_saves_on_yes() -> void:
	var ui: TownTuneOverlay = auto_free(load("res://scenes/ui/town_tune_overlay.tscn").instantiate())
	add_child(ui)
	Game.town_tune = TownTune.default_notes()
	ui.open()
	ui._slide.settle()
	ui._wait_timer = 0
	Audio.stop_melody()
	ui.cursor = 0
	_key(ui, KEY_UP)
	assert_int(ui.notes[0]).is_equal(8)
	_key(ui, KEY_RIGHT)
	assert_int(ui.cursor).is_equal(1)
	_key(ui, KEY_DOWN)
	assert_int(ui.notes[1]).is_equal(11)
	## Not saved until the prompt says Yes.
	assert_int(Game.town_tune[0]).is_equal(7)
	ui._on_prompt_answer(0)
	assert_int(Game.town_tune[0]).is_equal(8)
	assert_int(Game.town_tune[1]).is_equal(11)
	Game.town_tune = TownTune.default_notes()


func test_throw_it_out_keeps_the_old_tune() -> void:
	var ui: TownTuneOverlay = auto_free(load("res://scenes/ui/town_tune_overlay.tscn").instantiate())
	add_child(ui)
	Game.town_tune = TownTune.default_notes()
	ui.open()
	ui._slide.settle()
	ui._wait_timer = 0
	Audio.stop_melody()
	ui.cursor = 3
	_key(ui, KEY_UP)
	ui._on_prompt_answer(2)
	assert_array(Array(Game.town_tune)).is_equal(Array(TownTune.default_notes()))


func _key(ui: TownTuneOverlay, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ui._play_input(ev)


## `Na_Inst` with a villager's voice: the notes sing a G-major-ish scale above low G.
func test_sung_notes_rise_by_scale_steps() -> void:
	assert_float(TownTune.note_pitch(0)).is_equal(1.0)
	assert_float(TownTune.note_pitch(7)).is_equal_approx(2.0, 0.0001)
	assert_float(TownTune.note_pitch(3)).is_equal_approx(pow(2.0, 5.0 / 12.0), 0.0001)
	var v: Dictionary = DialogueVoice.melody_voice(1)
	assert_bool(v.has("spec") and v.has("phoneme") and v.has("pitch")).is_true()
