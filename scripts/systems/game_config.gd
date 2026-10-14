class_name GameConfig
extends RefCounted

## K.K.'s options before play (`Config_c`, `aNPS2_setup_sound_option` / `_voice_option` /
## `_yure_option`): sound output, how animals sound when they speak, and rumble. The original
## keeps them in the town save; the port keeps them in `user://config.cfg` so they hold before
## a town is loaded. Not an autoload.
##
## Rumble is `mVibctl_entry`: a strength, then attack / sustain / release programs and frame
## counts. Each program is reduced to one strength here (`Input.start_joy_vibration`).

enum Sound { STEREO, MONO, HEADPHONES }

const DEFAULT_PATH := "user://config.cfg"
const MONO_EFFECT := &"config_mono"

## `mVibctl_VIB_PROG_*` → strength.
enum Prog { NON, FFF, F, MF, MP, P, FUNBARI, ANAHORI, ANAUME, IMPACT, KI_GA_TAORERU, KI_WO_YUSURU, KORONODA, SURPRISE }
const PROG_STRENGTH: Array[float] = [0.0, 1.0, 0.8, 0.6, 0.45, 0.3, 0.9, 0.6, 0.5, 1.0, 0.85, 0.6, 0.9, 1.0]

## `Player_actor_set_viblation_*`: [power, sustain prog, attack, sustain, release].
const DIG := [100, Prog.ANAHORI, 0, 18, 0]
const DIG_STUMP := [100, Prog.KI_WO_YUSURU, 1, 60, 0]
const FILL := [80, Prog.ANAUME, 6, 60, 0]
const REFLECT_HARD := [100, Prog.IMPACT, 3, 9, 0]
const REFLECT_SOFT := [90, Prog.FFF, 2, 4, 0]
const SWING_NET := [100, Prog.FFF, 2, 4, 0]
const SHAKE_TREE := [100, Prog.KI_WO_YUSURU, 0, 34, 0]
const AXE_CUT := [100, Prog.KI_GA_TAORERU, 3, 36, 0]
const TUMBLE := [100, Prog.KORONODA, 3, 14, 0]
const REMOVE_GRASS := [90, Prog.FFF, 0, 1, 10]
## `aUKI_cast`: the bobber lands.
const BOBBER_LAND := [50, Prog.FFF, 0, 1, 15]
## `aNPS2_setup_yure_option`: "Rumble: ON" shows what it feels like.
const RUMBLE_ON := [75, Prog.FFF, 0, 16, 45]

static var path: String = DEFAULT_PATH
static var sound_mode: int = Sound.STEREO
static var voice_mode: int = DialogueVoice.Mode.ANIMALESE
static var rumble_on: bool = true
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		sound_mode = clampi(int(cfg.get_value("config", "sound_mode", Sound.STEREO)), 0, Sound.HEADPHONES)
		voice_mode = clampi(int(cfg.get_value("config", "voice_mode", DialogueVoice.Mode.ANIMALESE)), 0, DialogueVoice.Mode.SILENT)
		rumble_on = bool(cfg.get_value("config", "rumble", true))
	apply_sound()


## Back to the defaults (tests; a fresh install).
static func reset(p_path: String = DEFAULT_PATH) -> void:
	path = p_path
	sound_mode = Sound.STEREO
	voice_mode = DialogueVoice.Mode.ANIMALESE
	rumble_on = true
	_loaded = true
	apply_sound()


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("config", "sound_mode", sound_mode)
	cfg.set_value("config", "voice_mode", voice_mode)
	cfg.set_value("config", "rumble", rumble_on)
	cfg.save(path)


## `aNPS2_setup_sound_option`: choices Stereo / Mono / Headphones.
static func set_sound(index: int) -> void:
	ensure_loaded()
	sound_mode = clampi(index, 0, Sound.HEADPHONES)
	apply_sound()
	save()


## `aNPS2_setup_voice_option`: Animalese / Bebebese / Silence.
static func set_voice(index: int) -> void:
	ensure_loaded()
	voice_mode = [DialogueVoice.Mode.ANIMALESE, DialogueVoice.Mode.CLICK, DialogueVoice.Mode.SILENT][clampi(index, 0, 2)]
	save()


## `aNPS2_setup_yure_option`: choice 0 is on (and rumbles once), 1 off.
static func set_rumble(on: bool) -> void:
	ensure_loaded()
	rumble_on = on
	save()
	if on:
		rumble(RUMBLE_ON)


## The voice an animal speaker uses: the setting replaces Animalese. Signs and other
## clicking speakers keep their click.
static func voice_for(speaker_mode: int) -> int:
	ensure_loaded()
	return voice_mode if speaker_mode == DialogueVoice.Mode.ANIMALESE else speaker_mode


## Mono folds the master bus to its mid channel (`OSSetSoundMode(OS_SOUND_MODE_MONO)`);
## headphones play as stereo.
static func apply_sound() -> void:
	var bus: int = AudioServer.get_bus_index(&"Master")
	if bus < 0:
		return
	var at: int = -1
	for i: int in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).resource_name == MONO_EFFECT:
			at = i
			break
	if sound_mode == Sound.MONO and at < 0:
		var fx := AudioEffectStereoEnhance.new()
		fx.resource_name = MONO_EFFECT
		fx.pan_pullout = 0.0
		AudioServer.add_bus_effect(bus, fx)
	elif sound_mode != Sound.MONO and at >= 0:
		AudioServer.remove_bus_effect(bus, at)


## Strength and seconds of a `[power, prog, attack, sustain, release]` entry.
static func rumble_shape(entry: Array) -> Vector2:
	var strength: float = clampf(float(entry[0]) / 100.0, 0.0, 1.0) * PROG_STRENGTH[clampi(int(entry[1]), 0, PROG_STRENGTH.size() - 1)]
	var frames: int = int(entry[2]) + int(entry[3]) + int(entry[4])
	return Vector2(strength, float(frames) / DecompTime.FRAME_HZ)


## `mVibctl_entry`, unless rumble is off (`Save_Get(config).vibration_disabled`).
static func rumble(entry: Array) -> bool:
	ensure_loaded()
	if not rumble_on:
		return false
	var shape: Vector2 = rumble_shape(entry)
	if shape.x <= 0.0 or shape.y <= 0.0:
		return false
	for pad: int in Input.get_connected_joypads():
		Input.start_joy_vibration(pad, shape.x * 0.6, shape.x, shape.y)
	return true


## `aUKI_touch_vib_proc` / `aUKI_bite_vib_proc`: by the fish's shadow size (0–7).
static func fish_touch(size: int) -> bool:
	var table: Array = [[60, 0, 1, 10], [70, 0, 1, 10], [80, 0, 1, 10], [90, 0, 1, 10], [100, 0, 1, 10],
		[100, 1, 2, 9], [100, 2, 2, 7], [100, 2, 2, 7]]
	var row: Array = table[clampi(size, 0, 7)]
	return rumble([row[0], Prog.FFF, row[1], row[2], row[3]])


static func fish_bite(size: int) -> bool:
	var power: Array = [40, 50, 60, 70, 80, 90, 100, 100]
	return rumble([power[clampi(size, 0, 7)], Prog.IMPACT, 5, 60, 3])
