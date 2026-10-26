class_name KkTalk
extends BankTalk

## K.K. Slider's Saturday-night talk (`ac_npc_totakeke_talk.c_inc`, messages from
## `MSG_TOTAKEKE_START` 0x1B93).
##
## - Standing off to the side: "come up to the front row" (+0).
## - Front row, first time ever: his introduction (+0x0D, sets `TOTAKEKE_INTRODUCTION`);
##   first talk tonight (+1) or again (+2). All three ask "Want me to jam for you?".
## - Yes: if tonight's aircheck is already yours, "come back next week" (+4); else "Do you
##   have a request?" (+5): no → a random tune you don't have yet (+0x0A); yes → the title
##   editor (`mLE_TYPE_REQUEST`) — an exact title plays it (+9, or +8 for the three secret
##   songs), anything else gets one of his made-up tunes (+6).
## - Picking a record puts its aircheck in the pockets straight away (`aTTN_give_merody`),
##   or remembers the pockets were full; after the show `KkSlider` says which (+0x0C / +0x0B,
##   or +7 for a made-up tune).

const MSG_START := 0x1B93
const MSG_FRONT_ROW := MSG_START + 0
const MSG_HELLO := MSG_START + 1
const MSG_AGAIN := MSG_START + 2
const MSG_ALREADY := MSG_START + 4
const MSG_REQUEST := MSG_START + 5
const MSG_MADE_UP := MSG_START + 6
const MSG_NOT_MY_BAG := MSG_START + 7
const MSG_SECRET := MSG_START + 8
const MSG_FAR_OUT := MSG_START + 9
const MSG_RANDOM := MSG_START + 10
const MSG_POCKETS_FULL := MSG_START + 11
const MSG_AIRCHECK := MSG_START + 12
const MSG_INTRO := MSG_START + 13
## `aMKBC_NUM_GOOD_MD`: the random pick never lands on the three secret songs.
const GOOD_SONGS := 52
## `0x37 + RANDOM(3)`: tunes he makes up for a request he doesn't know.
const MADE_UP_FIRST := 55
const REQUEST_LEN := 16

enum After { NONE, GIVE, POCKETS_FULL, MADE_UP }

## Tonight's show (`aNTT_event_save_c`) and the player's own K.K. record
## (`TOTAKEKE_INTRODUCTION`, `aircheck_collect_bitfield`).
var show: Dictionary = {}
var player: Dictionary = {}
var inventory: Inventory
var in_front: bool = true
var rng: RandomNumberGenerator
## Chosen by the talk; `KkSlider` plays it.
var song: int = -1
var after: After = After.NONE
var request_text: String = ""


func _init(p_show: Dictionary = {}, p_player: Dictionary = {}, p_inventory: Inventory = null) -> void:
	show = p_show
	player = p_player
	inventory = p_inventory
	rng = RandomNumberGenerator.new()
	rng.randomize()


## `aNTT_wait` → `aNTT_set_norm_talk_info`.
func start_msg() -> int:
	if not in_front:
		return MSG_FRONT_ROW
	if not bool(player.get("introduced", false)):
		player["introduced"] = true
		return MSG_INTRO
	if not bool(show.get("hello", false)):
		return MSG_HELLO
	return MSG_AGAIN


func entered(msg_no: int) -> void:
	match msg_no:
		MSG_MADE_UP, MSG_NOT_MY_BAG:
			context.set_item_str(0, request_text)
		MSG_SECRET, MSG_FAR_OUT, MSG_RANDOM, MSG_AIRCHECK, MSG_POCKETS_FULL:
			var title: String = MinidiskCatalog.song_name(song) if song >= 0 and song < MinidiskCatalog.COUNT else ""
			context.set_item_str(0, title)
			context.set_item_str(1, title)
			context.set_item_str(2, title)


## `aNTT_talk_select0`: "Want me to jam for you?"
func picked(msg_no: int, index: int) -> int:
	if msg_no == MSG_HELLO or msg_no == MSG_AGAIN or msg_no == MSG_INTRO:
		show["hello"] = true
		if index == 0:
			return MSG_ALREADY if bool(show.get("aircheck", false)) else MSG_REQUEST
	return -1


## `aNTT_talk_select1`: "Do you have a request?" — 0 no, 1 yes.
func pick_step(msg_no: int, index: int) -> Dictionary:
	if msg_no != MSG_REQUEST:
		return {}
	if index == 1:
		return {"text": {"initial": "", "lines": 1, "len": REQUEST_LEN}}
	song = random_song()
	var tries: int = 0
	while tries < 3 and song == int(show.get("last_song", -1)):
		song = random_song()
		tries += 1
	show["last_song"] = song
	_give(song)
	return msg(MSG_RANDOM)


## `aNTT_talk_submenu2`: the typed title against the disc's record names.
func text_result(text: String) -> Dictionary:
	request_text = text
	var match_index: int = song_for_title(text)
	if match_index < 0:
		song = MADE_UP_FIRST + rng.randi_range(0, 2)
		after = After.MADE_UP
		return msg(MSG_MADE_UP)
	song = match_index
	_give(song)
	return msg(MSG_SECRET if song >= GOOD_SONGS else MSG_FAR_OUT)


## `mLE_move_Wait`: a byte-for-byte match with a record name (`mem_cmp`, padded to 16).
static func song_for_title(text: String) -> int:
	for i: int in MinidiskCatalog.COUNT:
		if MinidiskCatalog.song_name(i) == text:
			return i
	return -1


## `aMKBC_clip_search_merody`: a record the player hasn't been given, from the 52 regular
## ones; once all are collected the list starts over.
func random_song() -> int:
	var collected: int = int(player.get("collected", 0))
	var missing: Array[int] = []
	for i: int in GOOD_SONGS:
		if (collected >> i) & 1 == 0:
			missing.append(i)
	if missing.is_empty():
		player["collected"] = 0
		for i: int in GOOD_SONGS:
			missing.append(i)
	return missing[rng.randi_range(0, missing.size() - 1)]


## `aTTN_give_merody`: into the pockets now, or remember they were full.
func _give(index: int) -> void:
	var item: ItemData = ItemCatalog.get_item(MinidiskCatalog.item_id(index))
	if inventory == null or item == null or not inventory.has_space(1):
		after = After.POCKETS_FULL
		return
	after = After.GIVE
	inventory.add(item, 1)
	show["aircheck"] = true
	## `aMKBC_clip_check_merody`.
	if index < GOOD_SONGS:
		player["collected"] = int(player.get("collected", 0)) | (1 << index)


## The message after the show (`aNTT_set_force_talk_info`).
func after_show_msg() -> int:
	match after:
		After.GIVE:
			return MSG_AIRCHECK
		After.POCKETS_FULL:
			return MSG_POCKETS_FULL
		After.MADE_UP:
			return MSG_NOT_MY_BAG
	return -1


## A song was picked: the show starts when the window closes.
func wants_show() -> bool:
	return song >= 0
