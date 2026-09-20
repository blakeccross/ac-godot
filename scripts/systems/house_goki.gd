class_name HouseGoki
extends RefCounted

## Cockroaches in the player's house (`m_cockroach.c`, `ac_my_room_goki.c_inc`). Stay away from
## home for more than six days and they move in: one more for every day past the sixth (up to
## ten waiting). Each visit shows at most three; the rest stay in the walls. Stomp them by
## walking over them or by shoving furniture onto them; the ones you leave alive go back.

const INTERVAL_DAYS := 6
const MAX_STORED := 10
## `mCkRh_CAN_LOOK_GOKI_NUM` / `aMR_GOKI_MAX`.
const MAX_VISIBLE := 3
## `goki_random_make_data`: the side of the square of cells (from unit 1) a floor spawns in.
const FLOOR_SIZE: Dictionary = {
	&"player_main": [4, 6, 8, 8],
	&"player_upper": [6, 6, 6, 6],
	&"player_basement": [6, 6, 6, 6],
}


static func stored(house: House) -> int:
	return house.goki_count if house != null else 0


static func clamp_count(count: int) -> int:
	return clampi(count, 0, MAX_STORED)


## `mCkRh_SavePlayTime`.
static func save_play_time(house: House) -> void:
	if house == null:
		return
	house.goki_year = Clock.year
	house.goki_month = Clock.month
	house.goki_day = Clock.day


## Whole days since the house was last played (`lbRTC_GetIntervalDays`); 0 when never recorded.
static func days_away(house: House) -> int:
	if house == null or house.goki_year <= 0:
		return 0
	var then: int = _day_number(house.goki_year, house.goki_month, house.goki_day)
	return maxi(_day_number(Clock.year, Clock.month, Clock.day) - then, 0)


## `mCkRh_DecideNowGokiFamilyCount`, run when the game starts.
static func decide_family_count(house: House) -> void:
	if house == null:
		return
	if house.goki_year <= 0:
		save_play_time(house)
		return
	var gap: int = days_away(house)
	if gap > INTERVAL_DAYS:
		var count: int = gap if house.goki_count > 0 else gap - INTERVAL_DAYS
		house.goki_count = clamp_count(count + house.goki_count)


static func _day_number(year: int, month: int, day: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": day, "hour": 12}) / 86400)


## Cells a floor spawns cockroaches in (`aMR_RandomMakeIndoorGoki`): the first `size`×`size`
## block from unit 1 that holds no furniture.
static func free_cells(session: IndoorSession, house: House) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if session == null or session.room == null:
		return out
	var sizes: Array = FLOOR_SIZE.get(session.room.id, []) as Array
	if sizes.is_empty():
		return out
	var size: int = int(sizes[PlayerHouse.tier_of(house)])
	for z: int in range(1, size + 1):
		for x: int in range(1, size + 1):
			var cell := Vector2i(x, z)
			if session.room.is_inner(cell) and session.grid.occupant_at(cell) == &"":
				out.append(cell)
	return out


## Roaches that scatter when you walk in. Takes them out of the walls (`MinusGokiN_NowRoom`)
## and returns their spots: the first just behind the player, the rest anywhere free.
## `[{ "pos": Vector3, "fade": false }]`.
static func entry_spawns(
	session: IndoorSession, house: House, player_pos: Vector3, rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var want: int = mini(stored(house), MAX_VISIBLE)
	var cells: Array[Vector2i] = free_cells(session, house)
	if want <= 0 or cells.is_empty():
		return out
	for i: int in want:
		var spot: Vector3
		if i == 0:
			var offsets: Array[float] = [0.5, -0.5, 0.75, -0.75]
			spot = player_pos + Vector3(offsets[rng.randi() % offsets.size()], 0.0, -0.5)
			var cell: Vector2i = session.grid.world_to_cell(spot)
			if not (session.room.is_inner(cell) and session.grid.occupant_at(cell) == &""):
				continue
		else:
			var pick: Vector2i = cells[rng.randi() % cells.size()]
			spot = session.grid.cell_to_world(pick)
		spot.y = 0.0
		out.append({"pos": spot, "fade": false})
		house.goki_count = clamp_count(house.goki_count - 1)
	return out


## Furniture shoved off a spot uncovers one (`aMR_MakeGokiburi`): only while some are waiting
## and fewer than three are already out. It fades in.
static func furniture_spawn(
	session: IndoorSession, house: House, cell: Vector2i, visible_now: int
) -> Dictionary:
	if stored(house) <= 0 or visible_now >= MAX_VISIBLE or session == null:
		return {}
	house.goki_count = clamp_count(house.goki_count - 1)
	var pos: Vector3 = session.grid.cell_to_world(cell)
	pos.y = 0.0
	return {"pos": pos, "fade": true}


## Leaving the room: the survivors go back into the walls (`aMR_GokiInfoDt`).
static func return_survivors(house: House, alive: int) -> void:
	if house != null:
		house.goki_count = clamp_count(house.goki_count + alive)
