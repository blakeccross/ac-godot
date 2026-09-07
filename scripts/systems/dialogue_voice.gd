class_name DialogueVoice
extends RefCounted

## Animalese: `m_msg_sound` + `Na_VoiceSe` / `Sou_*Henkan` / emotion pitch. Not a Nas port.

enum Mode { ANIMALESE, CLICK, SILENT }

## `VOICE_STATUS_*` (`audio.h`) — drives `_18` / `_0C` emotion modulators.
enum Status { NORMAL, ANGRY, SAD, FUN, SLEEPY, GLOOMY }

## `mNpc_GetNpcSoundSpec` looks table → `sou_now_spec`.
const LOOKS_SOUND_SPEC: Array[int] = [4, 4, 2, 2, 3, 4]

## Spec → catalog voice folder (`Na_SpecChange` → seq 243/244/245 → sou_now_voice_seq 1/2/3).
const SPEC_TO_VOICE_SEQ: Dictionary = {
	2: 1,
	3: 2,
	4: 3,
	5: 1,
	6: 3,
	7: 1,
	8: 3,
	9: 1,
}

## Base volume `_08` and pitch `_14` from `sou_now_spec`.
const SPEC_VOL: Dictionary = {
	2: 0.65,
	3: 0.65,
	4: 0.65,
	5: 0.9,
	6: 0.9,
	7: 0.9,
	8: 0.9,
	9: 0.7,
}
const SPEC_PITCH: Dictionary = {
	2: 1.0,
	3: 1.0,
	4: 1.0,
	5: 1.0,
	6: 1.0,
	7: 1.3,
	8: 0.75,
	9: 0.65,
}

## `0x82` pitch bump by voice seq (`sou_now_voice_seq`).
const QUESTION_PITCH_BUMP: Dictionary = {1: 1.24, 2: 1.3, 3: 1.13}

## `Sou_TanboinHenkan` — vowel/letter → instrument (next code as digraph hint).
const TANBOIN: Dictionary = {
	0x5D: 0x01,
	0x5E: 0x07,
	0x5F: -1, ## depends on b — see tanboin()
	0x60: 0x09,
	0x61: 0x0A,
	0x62: 0x11,
	0x63: 0x12,
	0x64: 0x00,
	0x65: 0x14,
	0x66: 0x17,
	0x67: 0x18,
	0x68: 0x19,
	0x69: 0x1A,
	0x6A: 0x1B,
	0x6B: 0x1D,
	0x6C: 0x21,
	0x6D: 0x18,
	0x6E: 0x22,
	0x6F: 0x23,
	0x70: 0x26,
	0x71: 0x29,
	0x72: 0x2D,
	0x73: 0x2E,
	0x74: 0x31,
	0x75: 0x15,
	0x76: 0x30,
	0x53: 0x32,
	0x54: 0x33,
	0x55: 0x26,
	0x56: 0x27,
	0x57: 0x34,
	0x58: 0x35,
	0x59: 0x36,
	0x5A: 0x37,
	0x5B: 0x10,
	0x5C: 0x38,
}

## `Sou_ChouboinHenkan` overrides for long-vowel digraphs.
const CHOUBOIN: Dictionary = {
	0x5D: 0x02,
	0x65: 0x15,
	0x71: 0x2A,
	0x61: 0x0E,
	0x6B: 0x1E,
}

var mode: Mode = Mode.ANIMALESE
var sound_spec: int = 2
var status: Status = Status.NORMAL
var rng: RandomNumberGenerator

var _last_num: int = 0xFF
var _last_num2: int = 0xFF
var _deferred: int = 0
var _deferred_scale: int = 32
var _effect_counter: int = 0
var _effect_period: int = 0
var _sad_toguru: int = 0
var _pitch_bump: float = 1.0
var _vol_bump: float = 1.0


func _init() -> void:
	rng = RandomNumberGenerator.new()
	rng.randomize()


static func sound_spec_for_looks(looks: VillagerPersonality.Looks) -> int:
	var idx: int = int(looks)
	if idx < 0 or idx >= LOOKS_SOUND_SPEC.size():
		return 2
	return LOOKS_SOUND_SPEC[idx]


static func voice_seq_for_spec(spec: int) -> int:
	return int(SPEC_TO_VOICE_SEQ.get(spec, 1))


static func status_for_mood(mood: VillagerState.Mood) -> Status:
	match mood:
		VillagerState.Mood.ANGRY:
			return Status.ANGRY
		VillagerState.Mood.SAD:
			return Status.SAD
		VillagerState.Mood.HAPPY:
			return Status.FUN
		VillagerState.Mood.SLEEPY:
			return Status.SLEEPY
		VillagerState.Mood.PITFALL:
			return Status.GLOOMY
		_:
			return Status.NORMAL


static func vol_scale_to_db(scale: float) -> float:
	if scale <= 0.0001:
		return -80.0
	return 20.0 * log(scale) / log(10.0)


## Map a UTF-8 character to a raw `voice_array` code (`mMsg_sound_voice_get`).
static func raw_voice_code(ch: String) -> int:
	if ch.is_empty():
		return 0x85
	var code: int = ch.unicode_at(0)
	if code >= 65 and code <= 90:
		return 0x5D + (code - 65)
	if code >= 97 and code <= 122:
		return 0x5D + (code - 97)
	if code >= 48 and code <= 57:
		return 0x53 + (code - 48)
	match code:
		32:
			return 0x85
		10, 13:
			return 0x84
		33: # !
			return 0x80
		63: # ?
			return 0x82
		34, 39: # " '
			return 0x83
		46, 44, 59, 58: # . , ; :
			return 0x81
		_:
			return 0x85


static func is_punct_voice(code: int) -> bool:
	return code == 0xFF or (code >= 0x80 and code <= 0x86)


static func boin_shiin(code: int) -> int:
	## 0 = vowel-ish, 1 = consonant-ish, 2 = other (`Sou_BoinShiinCheck`).
	match code:
		0x5D, 0x61, 0x65, 0x6A, 0x6B, 0x71:
			return 0
		0x5E, 0x5F, 0x60, 0x62, 0x63, 0x64, 0x66, 0x67, 0x68, 0x69, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x72, 0x73, 0x74, 0x75, 0x76:
			return 1
		_:
			return 2


static func tanboin(a: int, b: int) -> int:
	if a == 0x5F:
		if b == 0x65 or b == 0x61:
			return 0x23
		return 0x18
	if TANBOIN.has(a):
		var v: int = int(TANBOIN[a])
		if v >= 0:
			return v
	return a


static func chouboin(a: int, b: int) -> int:
	if CHOUBOIN.has(a):
		return int(CHOUBOIN[a])
	## Same fallbacks as tanboin for letters without a long-vowel override.
	return tanboin(a, b)


static func connect_check(a: int, b: int, c: int) -> int:
	## `Sou_ConnectCheck` — English digraph → instrument id (may be > 0x38).
	match a:
		0x5D:
			match b:
				0x65:
					return 0x0F
				0x68:
					return 0x02
				0x6E:
					return 0x16
				0x6A:
					return 0x39
				0x6F:
					return 0x3A
		0x61:
			match b:
				0x5D:
					return 0x15
				0x6E:
					return 0x0D
		0x5E:
			match b:
				0x61:
					return 0x3B
				0x75:
					return 0x3C
		0x5F:
			if b == 0x64:
				return 0x08
		0x60:
			if b == 0x6B:
				return 0x3D
		0x62:
			match b:
				0x5D:
					return 0x35
				0x6B:
					return 0x34
		0x63:
			match b:
				0x61:
					return 0x17
				0x6B:
					return 0x3E
		0x64:
			match b:
				0x5D:
					return 0x3F
				0x61:
					return 0x40
				0x65:
					return 0x41
				0x6B:
					return 0x42
		0x65:
			match b:
				0x6E:
					return 0x0C
				0x81:
					return 0x05
				0x62:
					return 0x43
				0x6A:
					return 0x44
				0x6F:
					return 0x45
				0x70:
					return 0x46
		0x67:
			if b == 0x6F:
				return 0x31
		0x69:
			match b:
				0x61:
					return 0x47
				0x75:
					return 0x48
		0x6A:
			match b:
				0x5D:
					return 0x38
				0x63:
					return 0x1C
				0x6B:
					return 0x49
		0x6B:
			match b:
				0x6B:
					return 0x2A
				0x73:
					return 0x06
				0x75:
					return 0x1F
				0x71:
					return 0x20
				0x6E:
					return 0x2C
				0x62:
					return 0x4A
				0x64:
					return 0x4B
				0x67:
					return 0x4C
				0x6A:
					return 0x4D
		0x6E:
			if b == 0x61:
				return 0x0E
		0x6F:
			match b:
				0x61:
					return 0x37
				0x64:
					return 0x24
				0x65:
					return 0x36
				0x71:
					return 0x25
				0x6B:
					return 0x4F
		0x70:
			match b:
				0x64:
					return 0x28
				0x6B:
					return 0x50
		0x71:
			if b == 0x6C:
				return 0x51
		0x73:
			match b:
				0x61:
					return 0x52
				0x6B:
					return 0x33
		0x75:
			if b == 0x6B and c == 0x71:
				return 0x77
		0x76:
			if b == 0x61:
				return 0x32
	return a


func reset_line() -> void:
	_last_num = 0xFF
	_last_num2 = 0xFF
	_deferred = 0
	_pitch_bump = 1.0
	_vol_bump = 1.0
	_effect_counter = 0
	_effect_period = 0
	_sad_toguru = 0


func set_status(next: Status) -> void:
	status = next
	_effect_counter = 0
	_effect_period = 0
	_sad_toguru = 0


func configure(p_mode: Mode, p_spec: int, p_status: Status = Status.NORMAL) -> void:
	mode = p_mode
	sound_spec = p_spec
	set_status(p_status)
	reset_line()


## Legacy one-shot helper (no digraph peek / emotion session).
static func phoneme_for_char(ch: String) -> int:
	var raw: int = raw_voice_code(ch)
	match raw:
		0x81, 0x84, 0x85:
			return -1
		0x86:
			return -2
		0x80, 0x82, 0x83:
			return -1
	return tanboin(raw, 0xFF)


## Play pending digraph second beat (`Sou_SpecialRoutine10` / f=2), then this glyph.
func utter_glyph(ch: String, next_ch: String = "", next2_ch: String = "", at: Node = null) -> bool:
	var played := false
	if _deferred != 0 and mode == Mode.ANIMALESE:
		played = _play_phoneme(_resolve_deferred(), at) or played
		_deferred = 0
	match mode:
		Mode.SILENT:
			return played
		Mode.CLICK:
			var raw_c: int = raw_voice_code(ch)
			if raw_c == 0x81 or raw_c == 0x84:
				return played
			_play_bebe(at)
			return true
		_:
			pass
	var a: int = raw_voice_code(ch)
	var b: int = raw_voice_code(next_ch) if not next_ch.is_empty() else 0xFF
	var c: int = raw_voice_code(next2_ch) if not next2_ch.is_empty() else 0xFF
	return _voice_se_main(a, b, c, at) or played


## Static entry used by older call sites / tests.
static func utter(ch: String, p_mode: Mode, sound_spec: int, at: Node = null) -> bool:
	var voice := DialogueVoice.new()
	voice.configure(p_mode, sound_spec)
	return voice.utter_glyph(ch, "", "", at)


func _resolve_deferred() -> int:
	## f=2 path: `Sou_TanboinHenkan(a, sou_num3_org)` with a = deferred request.
	var a: int = _deferred
	if a == 0x61 and _last_num2 > 0x77 and boin_shiin(_last_num2) == 0 and boin_shiin(_last_num) == 1:
		return 0
	return tanboin(a, 0xFF)


func _voice_se_main(a_in: int, b_in: int, c_in: int, at: Node) -> bool:
	var a: int = a_in
	var b: int = b_in
	var c: int = c_in
	var org_a: int = a
	var r28: int = 0
	_pitch_bump = 1.0
	_vol_bump = 1.0
	if a == 0x85 and b == 0xFF and c == 0xFF:
		_last_num = org_a
		_last_num2 = b
		return false
	if a == 0x61 and b > 0x77 and boin_shiin(_last_num) == 0 and boin_shiin(_last_num2) == 1:
		a = b
		r28 = 4
	if b == 0x61 and c > 0x77 and boin_shiin(_last_num2) == 0 and boin_shiin(a) == 1:
		b = 0
		r28 = 4
	if r28 != 4:
		a = connect_check(a, b, c)
		r28 = 1 if a == org_a else 2
		if is_punct_voice(b):
			r28 = 3
			if is_punct_voice(_last_num2):
				r28 = 1
	match r28:
		1, 4:
			if boin_shiin(a) == 0 and boin_shiin(b) == 1 and c == 0x61:
				a = chouboin(a, b)
			else:
				a = tanboin(a, b)
			if b != 0 and not is_punct_voice(b) and b <= 0x76:
				_deferred = b
		3:
			if a > 0x77:
				_commit_last(org_a, b_in)
				return false
			a = _last_num2
			b = org_a
			c = b_in
			a = connect_check(a, b, c)
			if a < 0x53 or a > 0x76:
				_commit_last(org_a, b_in)
				return _handle_special_codes(org_a, at)
			a = tanboin(a, b)
		_:
			## Digraph already an instrument id from connect_check — play as-is.
			pass
	var triple_repeat: bool = org_a == _last_num2 and org_a == _last_num
	_commit_last(org_a, b_in)
	return _emit_resolved(a, org_a, triple_repeat, at)


func _commit_last(org_a: int, b: int) -> void:
	_last_num = org_a
	_last_num2 = b


func _handle_special_codes(raw: int, at: Node) -> bool:
	match raw:
		0x86:
			_play_bebe(at)
			return true
		0x81, 0x84, 0x85:
			return false
		0x82:
			var seq: int = voice_seq_for_spec(sound_spec)
			_pitch_bump = float(QUESTION_PITCH_BUMP.get(seq, 1.13))
			return false
		0x83:
			_vol_bump = 1.15
			return false
		0x80:
			## Melody `!` — skip (no per-animal melody bank yet).
			return false
	return false


func _emit_resolved(a: int, raw: int, triple_repeat: bool, at: Node) -> bool:
	if raw == 0x80:
		return _handle_special_codes(raw, at)
	## Spec 5/6: silent/punct → click.
	if sound_spec == 5 or sound_spec == 6:
		if raw == 0x81 or raw == 0x84 or raw == 0x85 or raw == 0x86:
			_play_bebe(at)
			return true
	else:
		if raw == 0x86:
			_play_bebe(at)
			return true
		if raw == 0x81 or raw == 0x84 or raw == 0x85:
			return false
		if raw == 0x82 or raw == 0x83:
			_handle_special_codes(raw, at)
			return false
	var phoneme: int = a
	if triple_repeat and sound_spec != 5 and sound_spec != 6 and raw <= 0x77:
		phoneme = (rng.randi() >> 2) & 0x3F
		if phoneme == 0:
			phoneme = 1
	if phoneme <= 0 or phoneme > 0x77:
		return false
	if raw == 0x85 or raw == 0x81 or raw == 0x84:
		return false
	return _play_phoneme(phoneme, at)


func _emotion_mods() -> Vector2:
	## Returns (pitch_mod `_18`, vol_mod `_0C`).
	if sound_spec == 5 or sound_spec == 6:
		return Vector2(1.0, 1.0)
	match status:
		Status.ANGRY:
			return _angry_mods()
		Status.SAD, Status.SLEEPY, Status.GLOOMY:
			return _sad_mods()
		Status.FUN:
			return _fun_mods()
		_:
			return Vector2(1.0, 1.0)


func _angry_mods() -> Vector2:
	if _effect_counter == 0:
		_effect_counter = (rng.randi() >> 6) + 0xA
	else:
		_effect_counter -= 1
	match _effect_counter:
		0, 1, 2, 9, 10:
			return Vector2(1.25, 1.25)
		3, 4:
			return Vector2(1.2, 1.2)
		_:
			return Vector2(0.9, 1.05)


func _sad_mods() -> Vector2:
	if _effect_counter == 0:
		_effect_period = (rng.randi() >> 6) + 0xE
		_effect_counter = 1
	elif _effect_counter == _effect_period:
		_effect_counter = 0
		_sad_toguru = 1 - _sad_toguru
	else:
		_effect_counter += 1
	var pitch: float
	var vol: float
	if _sad_toguru == 0:
		pitch = 1.0 - float(_effect_counter) * 0.022
		vol = 1.0 - float(_effect_counter) * 0.025
	else:
		pitch = 1.1 - float(_effect_counter) * 0.022
		vol = 1.1 - float(_effect_counter) * 0.025
	return Vector2(pitch, vol)


func _fun_mods() -> Vector2:
	if _effect_counter == 0:
		_effect_counter = (rng.randi() >> 6) + 0xA
	else:
		_effect_counter -= 1
	match _effect_counter:
		0, 1:
			return Vector2(1.05, 1.05)
		2:
			return Vector2(0.9, 1.15)
		_:
			return Vector2(1.15, 1.05)


func _play_phoneme(phoneme: int, at: Node) -> bool:
	var base_pitch: float = float(SPEC_PITCH.get(sound_spec, 1.0))
	var base_vol: float = float(SPEC_VOL.get(sound_spec, 0.65))
	var mods: Vector2 = _emotion_mods()
	var pitch: float = base_pitch * mods.x * _pitch_bump
	var vol_lin: float = base_vol * mods.y * _vol_bump
	var vol_db: float = vol_scale_to_db(vol_lin)
	var spec_folder: int = voice_seq_for_spec(sound_spec)
	if at != null:
		Audio.play_voice(spec_folder, phoneme, pitch, vol_db, at)
	else:
		Audio.play_voice(spec_folder, phoneme, pitch, vol_db)
	_pitch_bump = 1.0
	_vol_bump = 1.0
	return true


func _play_bebe(at: Node) -> void:
	if at != null:
		Audio.play_se(&"bebe", at)
	else:
		Audio.play_se(&"bebe")
