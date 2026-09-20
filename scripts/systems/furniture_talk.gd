class_name FurnitureTalk
extends RefCounted

## The conversations behind a tapped dresser or music player, run as a coroutine so the player
## stays put until the last message closes (`aMR_MessageControl`). The dialogue graphs decide
## the wording; this only carries out the answers (`storage_*` / `music_*` events).


static func run(host: Node, ctx: InteractionContext) -> bool:
	var pid: StringName = host.get("occupant_id") as StringName
	if Game.interior_session == null:
		return false
	var entry: FurniturePlacement = Game.interior_session.room.placement_by_id(pid)
	var data: FurnitureData = Game.interior_session.furniture_of(entry.furniture_id) if entry else null
	if entry == null or data == null:
		return false
	if data.is_music_player():
		await _run_music(entry, data, ctx)
	else:
		await _run_storage(entry, data, ctx)
	return true


## --- dresser / wardrobe / closet --------------------------------------------------------


static func _run_storage(entry: FurniturePlacement, data: FurnitureData, ctx: InteractionContext) -> void:
	var inv: Inventory = ctx.inventory if ctx != null and ctx.inventory != null else Game.inventory
	var is_owner: bool = Game.is_decorating()
	var events: Array[Dictionary] = await _play(
		FurnitureStorage.DIALOGUE_ID,
		FurnitureStorage.VAR_SCENE,
		FurnitureStorage.scene_for(entry, is_owner),
		func(dctx: DialogueContext) -> void: FurnitureStorage.fill_context(dctx, entry)
	)
	for event: Dictionary in events:
		match str(event.get("op", "")):
			"storage_put":
				await _storage_put_in(entry, inv)
			"storage_take":
				var result: StringName = FurnitureStorage.take_out(entry, int(event.get("index", 0)), inv)
				if result == &"full":
					await _play(
						FurnitureStorage.DIALOGUE_ID, FurnitureStorage.VAR_SCENE, &"pockets_full", Callable()
					)
	await _close_furniture(ctx, data)


static func _storage_put_in(entry: FurniturePlacement, inv: Inventory) -> void:
	if not inv.has_putin_candidates(&"any"):
		await _play(FurnitureStorage.DIALOGUE_ID, FurnitureStorage.VAR_SCENE, &"nothing_to_put", Callable())
		return
	Game.request_storage_putin(&"any")
	if Game.storage_putin_pending:
		var picked: StringName = await Game.storage_putin_resolved
		if picked == &"":
			return
		if inv.remove(picked, 1) > 0:
			return
		if not FurnitureStorage.put_in(entry, picked):
			var data: ItemData = ItemCatalog.get_item(picked)
			if data != null:
				inv.add(data, 1)


## Shut the door / drawer again (`mPlib_request_main_close_furniture_type1`).
static func _close_furniture(ctx: InteractionContext, data: FurnitureData) -> void:
	if data.is_music_player() or ctx == null or ctx.actor == null:
		return
	var actor: Node = ctx.actor
	if actor.has_method("play_storage_close"):
		await actor.call("play_storage_close", int(data.storage_type))


## --- music player -----------------------------------------------------------------------


static func _run_music(entry: FurniturePlacement, data: FurnitureData, ctx: InteractionContext) -> void:
	var inv: Inventory = ctx.inventory if ctx != null and ctx.inventory != null else Game.inventory
	var session: IndoorSession = Game.interior_session
	var house: House = Game.interiors.player_house()
	var is_owner: bool = Game.is_decorating()
	var events: Array[Dictionary] = await _play(
		FurnitureMusic.DIALOGUE_ID,
		FurnitureMusic.VAR_SCENE,
		FurnitureMusic.scene_for(entry, is_owner),
		func(dctx: DialogueContext) -> void: FurnitureMusic.fill_context(dctx, entry)
	)
	for event: Dictionary in events:
		match str(event.get("op", "")):
			"music_toggle":
				FurnitureMusic.set_switch(session, entry, not entry.on)
				Audio.play_se(&"light_on" if entry.on else &"light_off")
			"music_insert":
				await _music_insert(session, entry, house, inv)
			"music_box":
				await _music_box(session, entry, house)
	refresh_room_bgm()


static func _music_insert(
	session: IndoorSession, entry: FurniturePlacement, house: House, inv: Inventory
) -> void:
	if not inv.has_putin_candidates(&"minidisk"):
		await _play(FurnitureMusic.DIALOGUE_ID, FurnitureMusic.VAR_SCENE, &"no_disc", Callable())
		return
	Game.request_storage_putin(&"minidisk")
	if not Game.storage_putin_pending:
		return
	var picked: StringName = await Game.storage_putin_resolved
	if picked == &"":
		return
	var result: Dictionary = FurnitureMusic.insert_disc(session, entry, house, picked, inv)
	if result["result"] == &"duplicate":
		await _play(FurnitureMusic.DIALOGUE_ID, FurnitureMusic.VAR_SCENE, &"duplicate", Callable())
	elif result["result"] == &"ok":
		Audio.play_se(&"light_on")


## Step through the songs the house owns and play one (`mSM_OVL_MUSIC`).
static func _music_box(session: IndoorSession, entry: FurniturePlacement, house: House) -> void:
	var songs: Array[int] = MinidiskCatalog.box_songs(house)
	if songs.is_empty():
		await _play(FurnitureMusic.DIALOGUE_ID, FurnitureMusic.VAR_SCENE, &"box_empty", Callable())
		return
	var cursor: Array[int] = [maxi(songs.find(FurnitureMusic.song_of(entry)), 0)]
	var picked: Array[int] = [-1]
	await _play(
		FurnitureMusic.DIALOGUE_ID,
		FurnitureMusic.VAR_SCENE,
		&"box_pick",
		func(dctx: DialogueContext) -> void: dctx.item0 = MinidiskCatalog.song_name(songs[cursor[0]]),
		func(event: Dictionary, dctx: DialogueContext) -> void:
			match str(event.get("op", "")):
				"music_step":
					cursor[0] = posmod(cursor[0] + int(event.get("dir", 1)), songs.size())
					dctx.item0 = MinidiskCatalog.song_name(songs[cursor[0]])
				"music_play":
					picked[0] = songs[cursor[0]]
	)
	if picked[0] >= 0:
		FurnitureMusic.select_song(session, entry, picked[0])
		Audio.play_se(&"light_on")


static func refresh_room_bgm() -> void:
	var host: Node = Game.get_tree().get_first_node_in_group("interior") if Game.get_tree() != null else null
	if host != null and host.has_method("refresh_bgm"):
		host.call("refresh_bgm")


## --- plumbing ---------------------------------------------------------------------------


## Play one scene of a dialogue and return the events its answers fired.
static func _play(
	dialogue_id: StringName,
	scene_var: String,
	scene: StringName,
	prepare: Callable,
	on_event: Callable = Callable()
) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var tree: SceneTree = Game.get_tree()
	var ui: Node = tree.get_first_node_in_group("dialogue_ui") if tree != null else null
	var data: DialogueData = DialogueCatalog.conversation(dialogue_id)
	if ui == null or data == null or not ui.has_method("play"):
		return events
	var dctx: DialogueContext = DialogueContext.from_game()
	if prepare.is_valid():
		prepare.call(dctx)
	dctx.set_var(scene_var, String(scene))
	var capture := func(event: Dictionary) -> void:
		events.append(event)
		if on_event.is_valid():
			on_event.call(event, dctx)
	ui.connect("event_fired", capture)
	ui.call("play", data, dctx)
	if not ui.has_method("is_open") or bool(ui.call("is_open")):
		await ui.closed
	ui.disconnect("event_fired", capture)
	return events
