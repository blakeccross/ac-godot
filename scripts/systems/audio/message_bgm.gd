class_name MessageBgm
extends RefCounted

## Music cues written into message text (`BGMMAKE` / `BGMDELETE` control codes →
## `mMsg_sound_bgm_make` / `mMsg_sound_bgm_delete`). The importer turns them into
## `bgm_make` / `bgm_delete` dialogue events; `DialogueRunner` applies them here.
##
## `mMsg_bgm_num`: 0 quiet, 1 `INTRO_ARRIVE`, 2 `INTRO_RCN_GUIDE`, 3 `INTRO_SELECT_HOUSE`,
## 4 `INTRO_SELECT_HOUSE2`, 5 `RESET`, 6 quiet-the-field, 7 `RESET2`, 8 `BGM_122`.
## `mMsg_bgm_stop`: 0 normal fade (0x168), 1 quick (cut), 2 Resetti.

const QUIET := 0
const FIELD_QUIET := 6
const STOP_QUICK := 1
const TRACKS: Array[StringName] = [
	&"", &"intro_arrive", &"intro_rcn_guide", &"intro_select_house", &"intro_select_house2",
	&"reset", &"", &"reset2", &"122",
]


static func track(bgm: int) -> StringName:
	return TRACKS[bgm] if bgm >= 0 and bgm < TRACKS.size() else &""


## `mMsg_sound_bgm_make`: a quiet request stops the music; anything else plays over it.
static func make(bgm: int, stop: int) -> void:
	if bgm == QUIET or bgm == FIELD_QUIET:
		_stop(stop)
		return
	var id: StringName = track(bgm)
	if id != &"" and BgmCatalog.stream_for(id) != null:
		Audio.play_bgm(id)


## `mMsg_sound_bgm_delete`: drop that demo track if it is the one playing (the next `make`
## on the same page takes over; a lone delete leaves silence, as `ps_demo` removal does here).
static func delete(bgm: int, stop: int) -> void:
	if bgm == QUIET:
		return
	var id: StringName = track(bgm)
	if id != &"" and Audio.current_id == id:
		_stop(stop)


static func _stop(stop: int) -> void:
	if stop != STOP_QUICK:
		Audio.stop_bgm()
		return
	var fade: float = Audio.fade_sec
	Audio.fade_sec = 0.0
	Audio.stop_bgm()
	Audio.fade_sec = fade
