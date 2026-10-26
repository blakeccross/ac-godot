class_name FurnitureMusic
extends RefCounted

## Music players (`aFTR_INTERACTION_MUSIC_DISK`; `ac_my_room_msg_ctrl.c_inc` MD states). A player
## holds one song. Putting a disc in adds it to the house's music box and uses the disc up
## (`mTG_putin_proc` for `mSM_IV_OPEN_MINIDISK`); the box then plays any owned song for free.
## Only one player sounds at a time (`aMR_OneMDSwitchOn_TheOtherSwitchOff`) and it replaces the
## room's background music (`aMR_ChangeMDBgm`).

const DIALOGUE_ID := &"furniture_music"
const VAR_SCENE := "music_scene"
## `BGM_SPORTSFAIR_AEROBICS`: the radio-exercise set plays on its own switch, no disc.
const AEROBICS_BGM := &"sportsfair_aerobics"


static func song_of(entry: FurniturePlacement) -> int:
	if entry == null or entry.stored.is_empty():
		return -1
	return MinidiskCatalog.index_of(StringName(entry.stored[0]))


static func scene_for(entry: FurniturePlacement, is_owner: bool) -> StringName:
	var has_disc: bool = song_of(entry) >= 0
	if not is_owner:
		return &"other_music" if has_disc else &"other_music_empty"
	if not has_disc:
		return &"music_empty"
	return &"music_on" if entry.on else &"music_off"


static func fill_context(ctx: DialogueContext, entry: FurniturePlacement) -> void:
	if ctx == null:
		return
	var song: int = song_of(entry)
	ctx.item0 = MinidiskCatalog.song_name(song) if song >= 0 else ""


## A disc from the pockets. `{ "result": &"ok" | &"duplicate" | &"none", "song": int }`.
static func insert_disc(
	session: IndoorSession,
	entry: FurniturePlacement,
	house: House,
	disc_id: StringName,
	inventory: Inventory
) -> Dictionary:
	var song: int = MinidiskCatalog.index_of(disc_id)
	if entry == null or song < 0:
		return {"result": &"none", "song": -1}
	if MinidiskCatalog.box_has(house, song):
		## `mWR_WARNING_MUSIC2`: the box already has it — the disc stays in your pocket.
		return {"result": &"duplicate", "song": song}
	if inventory == null or inventory.remove(disc_id, 1) > 0:
		return {"result": &"none", "song": song}
	MinidiskCatalog.box_add(house, song)
	select_song(session, entry, song)
	return {"result": &"ok", "song": song}


## Play `song` from this player (a disc just put in, or the music box).
static func select_song(session: IndoorSession, entry: FurniturePlacement, song: int) -> void:
	entry.stored = PackedStringArray([String(MinidiskCatalog.item_id(song))])
	set_switch(session, entry, true)


## Switch a player on or off; switching one on silences the others.
static func set_switch(session: IndoorSession, entry: FurniturePlacement, on: bool) -> void:
	if on and song_of(entry) < 0 and not _is_radio(session, entry):
		return
	entry.on = on
	if not on or session == null or session.room == null:
		return
	for other: FurniturePlacement in session.room.placements:
		if other != null and other != entry and _is_player(session, other):
			other.on = false


## BGM id the room should play right now (`aMR_ChangeMDBgm`), or `&""` for the room's own.
static func active_bgm(room: Room) -> StringName:
	if room == null:
		return &""
	for entry: FurniturePlacement in room.placements:
		if entry == null or not entry.on:
			continue
		var data: FurnitureData = ItemCatalog.get_item(entry.furniture_id) as FurnitureData
		if data != null and data.radio_aerobics:
			return AEROBICS_BGM
		if data == null or not data.is_music_player():
			continue
		var song: int = song_of(entry)
		if song >= 0:
			return MinidiskCatalog.bgm_id(song)
	return &""


static func _is_radio(session: IndoorSession, entry: FurniturePlacement) -> bool:
	var data: FurnitureData = session.furniture_of(entry.furniture_id) if session != null else null
	return data != null and data.radio_aerobics


static func _is_player(session: IndoorSession, entry: FurniturePlacement) -> bool:
	var data: FurnitureData = session.furniture_of(entry.furniture_id)
	return data != null and (data.is_music_player() or data.radio_aerobics)
