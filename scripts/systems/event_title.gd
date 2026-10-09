class_name EventTitle
extends RefCounted

## The event title card (`title_fade` → `mDemo_TYPE_EVENTMSG`, `set_emsg_default`): the first
## time a festival starts, or stops, with the player outdoors, the field fades out, the
## event is set up behind the black, its announcement shows in the message window
## (0x1743 + n to open, 0x1799 + n to close) and the field fades back in. Whether the opening
## card has run is the event's keep flag (`mEv_set_keep`), kept in the save.

const START_MSG := 0x1743
const END_MSG := 0x1799
const KEEP_AREA := &"title_keep"
## `scene_delay_timer`: 30 ticks of black after the window closes.
const AFTER_SEC := 30.0 / 60.0

## `get_title_no_for_event`.
const TITLE_NO := {
	&"fireworks_show": 0,
	&"cherry_blossom_festival": 1,
	&"sports_fair_aerobics": 2,
	&"sports_fair_foot_race": 3,
	&"sports_fair_ball_toss": 4,
	&"sports_fair_tug_of_war": 5,
	&"morning_aerobics": 6,
	&"harvest_moon_festival": 7,
	&"meteor_shower": 8,
	&"new_years_eve_countdown": 9,
	&"new_years_day": 10,
	&"fishing_tourney_1": 11,
	&"fishing_tourney_2": 11,
	&"halloween": 12,
	&"toy_day_jingle": 13,
	&"groundhog_day": 14,
	&"harvest_festival": 15,
}


static func message(id: StringName, opening: bool) -> int:
	if not TITLE_NO.has(id):
		return -1
	return (START_MSG if opening else END_MSG) + int(TITLE_NO[id])


## What the card for `id` should do now: 1 open, -1 close, 0 nothing. `keep` holds the day
## each opening card ran; a close for a card kept on another day is dropped quietly.
static func due(id: StringName, active: bool, keep: Dictionary, today: String) -> int:
	if not TITLE_NO.has(id):
		return 0
	var kept: bool = keep.has(String(id))
	if active and not kept:
		return 1
	if not active and kept:
		if str(keep[String(id)]) != today:
			keep.erase(String(id))
			return 0
		return -1
	return 0


## Fade out, run `between` (the event's setup or teardown), show the message on black,
## fade back in.
static func play(tree: SceneTree, msg: int, between: Callable) -> void:
	if tree == null:
		between.call()
		return
	await SceneTransition.play_wipe_out()
	between.call()
	var ui := DialogueOverlay.find(tree)
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % msg))
	if ui != null and data != null:
		var layer: int = ui.layer
		## Over the wipe, as `mMsg_request_main_appear` draws on the black.
		ui.layer = SceneTransition.layer + 1
		ui.play(data, DialogueContext.new())
		if ui.is_open():
			await ui.closed
		ui.layer = layer
	await tree.create_timer(AFTER_SEC).timeout
	await SceneTransition.play_wipe_in()
