class_name HappyRoomAcademy
extends RefCounted

## The Happy Room Academy (`m_mark_room.c`, `m_mark_room_ovl.c`). At game start, outside
## Nook's first job: a new member gets the welcome letter (0x1EF); otherwise, once a day, a
## house whose layout changed on an earlier day is scored and graded by letter, and an
## unchanged one has a 2-in-10 chance of a tip (0x1DC + one of 19, none repeated until all
## have gone). Changing the main or upper room marks the house updated and dated today
## (`mMkRm_ReportChangePlayerRoom`), so the score comes on a later day. Letters are on the
## wing paper (51).
##
## Scoring a floor (`mMkRm_MarkRoomOneFloor`, units 1…4/6/8 by size): points by where each
## piece, the wallpaper and the carpet come from; the five necessities (+4,400, or +16,000
## in one series); a whole base series (+48,000, +4,800 / +10,000 with its wallpaper and / or
## carpet); a theme series (7,000 a piece + 15,000 with both, or 10,000 for matching both
## alone) and −4,000 per piece outside it; each complete set (3,000 a piece); 777 per lucky
## piece; −800 per piece facing the wall it stands against; −1 per loose item. The upper
## floor counts only origins, sets, luck, facing and clutter. Never below zero. The letter
## says what stood out, or grades the total; 70,000 and 100,000 first bring the house and
## manor models. Tables come from the pipeline (`items/hra.json`, `tools/asset_pipeline/hra.py`).

const DATA_PATH := "res://assets/generated/items/hra.json"
const UNIT_MAX: Array[int] = [5, 7, 9, 9]
const HINT_NUM := 19
const HINT_BASE := 0x1DC
const WELCOME := 0x1EF
const PAPER := 51
const REWARD0_POINTS := 70000
const REWARD1_POINTS := 100000
const REWARD0_LETTER := 0x221
const REWARD1_LETTER := 0x222
## FTR_NOG_MYHOME2 / 4 (house model, manor model).
const REWARD0_PRESENT := &"ftr_1033"
const REWARD1_PRESENT := &"ftr_1034"

const SERIES_ONE := 0
const SERIES_BASE := 1
const SERIES_THEME := 2
const SERIES_SET := 3
const SERIES_OTHER := 53
const NECESSITY_NUM := 6
const NOT_NECESSITY := 5
const SURFACE := 1

const BIT_NECESSITIES := 1 << 0
const BIT_NECESSITIES_SAME := 1 << 1
const BIT_BASE_COMPLETE := 1 << 2
const BIT_BASE_WALL_OR_FLOOR := 1 << 3
const BIT_BASE_WALL_AND_FLOOR := 1 << 4
const BIT_THEME_WALL_AND_FLOOR := 1 << 5
const BIT_THEME_COMPLETE := 1 << 6
const BIT_THEME_OBSTACLE := 1 << 7
const BIT_BAD_DIRECTION := 1 << 16
const BIT_LETS_CLEAN := 1 << 17
const BIT_SET_COMPLETE := 1 << 32
const BIT_SERIES_STARTED := 1 << 33
const BIT_BASE_ALMOST := 1 << 34
const BIT_SERIES_ALMOST := 1 << 35

const EVAL_BASE_POINT := 1
const EVAL_NECESSITY := 2
const EVAL_BASE_SERIES := 4
const EVAL_THEME_SERIES := 8
const EVAL_SET_SERIES := 16
const EVAL_LUCKY := 32
const EVAL_DIRECTION := 64
const EVAL_CLEAN := 128
const FULL := 255
const UPPER_MODE := EVAL_BASE_POINT | EVAL_SET_SERIES | EVAL_LUCKY | EVAL_DIRECTION | EVAL_CLEAN

## Membership and the day's mark (`hra_member`, `house_updated`, `hra_mark_time`,
## `hra_mark_info`, `hra_reward0/1`).
var member: bool = false
var updated: bool = false
var mark_date: Vector3i = Vector3i.ZERO
var hint_bits: int = 0
var reward0: bool = false
var reward1: bool = false
## `mEv_SAVED_HRAWAIT` / `HRATALK`: the first job done, Nook tells you about the Academy the
## next day; no marks until he has.
var talk: int = Talk.NONE

enum Talk { NONE, WAIT, DUE }
## Nook's introduction (`aNSC_set_talk_info_start_wait4`, `aNSC_get_msg_no(-1)`).
const NOOK_TALK := 0x082A

static var _data: Dictionary = {}
static var _visual_index: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_data = parsed
			_assign_groups()
	return _data


static func available() -> bool:
	return not data().is_empty()


## `mMkRm_AssignIdxInGroup`: numbers each series' pieces; base series keep their
## necessity slots (0–4) and number the rest from 5; counts go on the series.
static func _assign_groups() -> void:
	var ftr: Array = _data["ftr"]
	var series: Array = _data["series"]
	var counts: Array = []
	counts.resize(series.size())
	counts.fill(0)
	var next: Array = []
	next.resize(series.size())
	for s: int in series.size():
		next[s] = NOT_NECESSITY if int(series[s][0]) == SERIES_BASE else 0
	for i: int in ftr.size():
		var row: Array = ftr[i]
		var s: int = int(row[0])
		if s < 0 or s >= series.size():
			continue
		if int(series[s][0]) != SERIES_BASE or int(row[1]) >= NOT_NECESSITY:
			row[1] = next[s]
			next[s] = int(next[s]) + 1
		counts[s] = int(counts[s]) + 1
	_data["series_count"] = counts


## `ftr_<n>` or an authored piece's model to its disc furniture index, −1 if none.
static func ftr_index(furniture_id: StringName) -> int:
	var id := String(furniture_id)
	if id.begins_with(FtrCatalog.ID_PREFIX) and id.substr(4).is_valid_int():
		return id.substr(4).to_int()
	var item: ItemData = ItemCatalog.get_item(furniture_id)
	if not (item is FurnitureData):
		return -1
	if _visual_index.is_empty():
		for i: int in FtrCatalog.count():
			_visual_index[str(FtrCatalog.row(i).get("visual", ""))] = i
	return int(_visual_index.get(String((item as FurnitureData).visual_id), -1))


## One piece on a floor, in HRA units (1 … size − 1 inside the walls).
class Piece:
	var index: int
	var unit: Vector2i
	var facing: int
	var layer: int
	var units: Array[Vector2i] = []


## A room's pieces: anchor unit, facing, layer and every unit it covers.
static func pieces_of(room: Room) -> Array[Piece]:
	var out: Array[Piece] = []
	if room == null:
		return out
	for p: FurniturePlacement in room.placements:
		if p == null:
			continue
		var idx: int = ftr_index(p.furniture_id)
		if idx < 0:
			continue
		var piece := Piece.new()
		piece.index = idx
		piece.unit = p.cell - room.inner_origin + Vector2i.ONE
		piece.facing = int(p.facing)
		piece.layer = p.layer
		var data_item: ItemData = ItemCatalog.get_item(p.furniture_id)
		var size: Vector2i = p.resolved_footprint(data_item as FurnitureData)
		if piece.facing == 1 or piece.facing == 3:
			size = Vector2i(size.y, size.x)
		for dz: int in size.y:
			for dx: int in size.x:
				piece.units.append(piece.unit + Vector2i(dx, dz))
		out.append(piece)
	return out


static func _row(idx: int) -> Array:
	var ftr: Array = data()["ftr"]
	return ftr[idx] if idx >= 0 and idx < ftr.size() else [SERIES_OTHER, NOT_NECESSITY, 0, 0, 0, 0]


## `mMkRm_CheckEdgeZone`: a unit against the wall the piece faces.
static func edge_zone(unit: Vector2i, facing: int, room_size: int) -> bool:
	var far: int = [4, 6, 8, 8][clampi(room_size, 0, 3)]
	match facing:
		0:
			return unit.y == far
		1:
			return unit.x == far
		2:
			return unit.y == 1
		3:
			return unit.x == 1
	return false


## A wallpaper's / carpet's disc index; −1 for one of the player's designs
## (`WALL_IS_MY_ORIG`), 0 for the built-in defaults.
static func wall_index(style_id: StringName, prefix: String) -> int:
	var idx: int = InteriorStyleCatalog.style_index(style_id, prefix)
	if idx >= 0:
		return idx
	return -1 if String(style_id).contains("design") else 0


## `mMkRm_MarkRoomOneFloor`. Returns {points, bits, base_rec, theme_rec, series}.
static func score_floor(pieces: Array[Piece], room_size: int, wall: int, floor_idx: int, mode: int,
		loose_items: int = 0) -> Dictionary:
	var d := data()
	var ut_max: int = UNIT_MAX[clampi(room_size, 0, 3)]
	var series: Array = d["series"]
	var counts: Array = d["series_count"]
	var inside: Array[Piece] = []
	for p: Piece in pieces:
		if p.unit.x >= 1 and p.unit.y >= 1 and p.unit.x < ut_max and p.unit.y < ut_max:
			inside.append(p)
	var search: Array = []
	search.resize(series.size())
	search.fill(0)
	for p: Piece in inside:
		var row: Array = _row(p.index)
		if int(row[0]) != SERIES_OTHER:
			search[int(row[0])] = int(search[int(row[0])]) | (1 << int(row[1]))
	var points := 0
	var bits := 0
	var base_rec := {}
	var theme_rec := {}
	var series_name := ""
	var theme_done := false
	var theme_idx := -1
	if mode & EVAL_BASE_POINT:
		var birth: Array = d["birth_points"]
		for p: Piece in inside:
			points += int(birth[int(_row(p.index)[4])])
		var mine: int = int(d["birth_my_original"])
		points += int(birth[mine]) if floor_idx < 0 else int(birth[int(d["floor_from"][clampi(floor_idx, 0, 66)])])
		points += int(birth[mine]) if wall < 0 else int(birth[int(d["wall_from"][clampi(wall, 0, 66)])])
	if mode & EVAL_NECESSITY:
		var perfect: int = (1 << (NECESSITY_NUM - 1)) - 1
		var all_series := 0
		var same := false
		for s: int in series.size():
			if int(series[s][0]) == SERIES_BASE:
				all_series |= int(search[s])
				if (int(search[s]) & perfect) == perfect:
					same = true
					break
		if same:
			points += 16000
			bits |= BIT_NECESSITIES_SAME
		elif (all_series & perfect) == perfect:
			points += 4400
			bits |= BIT_NECESSITIES
	if mode & EVAL_BASE_SERIES:
		for s: int in series.size():
			if int(series[s][0]) != SERIES_BASE or int(counts[s]) == 0:
				continue
			var match_idx: int = int(series[s][1])
			if (int(search[s]) & 0x3FF) == 0x3FF:
				points += 48000
				bits |= BIT_BASE_COMPLETE
				if wall == match_idx and floor_idx == match_idx:
					points += 10000
					bits |= BIT_BASE_WALL_AND_FLOOR
				elif wall == match_idx:
					points += 4800
					base_rec = {"kind": "carpet", "index": match_idx}
					bits |= BIT_BASE_WALL_OR_FLOOR
				elif floor_idx == match_idx:
					points += 4800
					base_rec = {"kind": "wall", "index": match_idx}
					bits |= BIT_BASE_WALL_OR_FLOOR
				break
			var have := _have_missing(int(search[s]), int(counts[s]))
			if have.x == int(counts[s]) - 1:
				base_rec = {"kind": "ftr", "index": _remaining(s, have.y)}
				bits |= BIT_BASE_ALMOST
				break
			elif have.x >= 6:
				bits |= BIT_SERIES_STARTED
				break
	if mode & EVAL_THEME_SERIES:
		var result := _theme(search, counts, series, wall, floor_idx)
		points += int(result["points"])
		bits |= int(result["bits"])
		theme_done = bool(result["done"])
		theme_idx = int(result["theme"])
		if result.has("rec"):
			theme_rec = result["rec"]
		if result.has("series"):
			series_name = str(result["series"])
	if mode & EVAL_SET_SERIES:
		for s: int in series.size():
			if int(series[s][0]) != SERIES_SET or int(counts[s]) == 0:
				continue
			var perfect: int = (1 << int(counts[s])) - 1
			if (int(search[s]) & perfect) == perfect:
				points += int(counts[s]) * 3000
				bits |= BIT_SET_COMPLETE
	if mode & EVAL_LUCKY:
		for p: Piece in inside:
			if int(_row(p.index)[3]) != 0:
				points += 777
	if mode & EVAL_DIRECTION:
		var facing_wall := 0
		for p: Piece in inside:
			if int(_row(p.index)[2]) == 0:
				continue
			for u: Vector2i in p.units:
				if edge_zone(u, p.facing, room_size):
					facing_wall += 1
					break
		if facing_wall > 0:
			points -= facing_wall * 800
			bits |= BIT_BAD_DIRECTION
	if (mode & EVAL_THEME_SERIES) and theme_done and theme_idx != -1:
		var obstacles := 0
		for p: Piece in inside:
			if int(_row(p.index)[0]) != theme_idx:
				obstacles += 1
		if obstacles > 0:
			points -= obstacles * 4000
			bits |= BIT_THEME_OBSTACLE
	if (mode & EVAL_CLEAN) and loose_items > 0:
		points -= loose_items
		bits |= BIT_LETS_CLEAN
	return {"points": maxi(points, 0), "bits": bits, "base_rec": base_rec, "theme_rec": theme_rec,
		"series": series_name}


## `mMkRm_EvaluateThemeSeriesComplete`.
static func _theme(search: Array, counts: Array, series: Array, wall: int, floor_idx: int) -> Dictionary:
	var out := {"points": 0, "bits": 0, "done": false, "theme": -1}
	for s: int in series.size():
		if int(series[s][0]) != SERIES_THEME or int(counts[s]) == 0:
			continue
		var perfect: int = (1 << int(counts[s])) - 1
		var match_idx: int = int(series[s][1])
		if int(search[s]) == perfect:
			out["series"] = str(data()["series_names"][s])
			if wall == match_idx and floor_idx == match_idx:
				out["points"] = int(out["points"]) + int(counts[s]) * 7000 + 15000
				out["theme"] = s
				out["bits"] = int(out["bits"]) | BIT_THEME_COMPLETE
				out["done"] = true
				return out
			if wall == match_idx and floor_idx != match_idx:
				out["bits"] = int(out["bits"]) | BIT_SERIES_ALMOST
				## The game names a carpet by the floor's own index here (a known slip).
				out["rec"] = {"kind": "carpet", "index": floor_idx}
			elif wall != match_idx and floor_idx == match_idx:
				out["bits"] = int(out["bits"]) | BIT_SERIES_ALMOST
				out["rec"] = {"kind": "wall", "index": wall}
		else:
			var have := _have_missing(int(search[s]), int(counts[s]))
			if int(counts[s]) == have.x + 1:
				if wall == match_idx and floor_idx == match_idx:
					out["rec"] = {"kind": "ftr", "index": _remaining(s, have.y)}
					out["bits"] = int(out["bits"]) | BIT_SERIES_ALMOST
			elif have.x >= 6:
				out["bits"] = int(out["bits"]) | BIT_SERIES_STARTED
	for s: int in series.size():
		if int(series[s][0]) == SERIES_THEME and int(counts[s]) != 0 \
				and wall == int(series[s][1]) and floor_idx == int(series[s][1]):
			out["points"] = int(out["points"]) + 10000
			out["bits"] = int(out["bits"]) | BIT_THEME_WALL_AND_FLOOR
			return out
	return out


## (pieces owned, the last group slot missing).
static func _have_missing(found: int, count: int) -> Vector2i:
	var have := 0
	var missing := 0
	for j: int in count:
		if (found >> j) & 1:
			have += 1
		else:
			missing = j
	return Vector2i(have, missing)


## `mMkRm_GetRemainOneFtr`.
static func _remaining(s: int, group: int) -> int:
	var ftr: Array = data()["ftr"]
	for i: int in ftr.size():
		if int(ftr[i][0]) == s and int(ftr[i][1]) == group:
			return i
	return -1


## `mMkRm_DecideLetterNo`: rewards first, then one of three blocks of letter bits (highest
## with a letter), then the grade by total. Returns [handbill, present].
func decide_letter(points: int, bits: int, room_size: int, rng: RandomNumberGenerator) -> Array:
	if points >= REWARD0_POINTS and not reward0:
		return [REWARD0_LETTER, REWARD0_PRESENT]
	if points >= REWARD1_POINTS and not reward1:
		return [REWARD1_LETTER, REWARD1_PRESENT]
	var table: Array = data()["letter_no"]
	var block: int = rng.randi_range(0, 2)
	for i: int in range(15, -1, -1):
		var idx: int = i + block * 16
		if (bits >> idx) & 1 and int(table[idx]) != -1:
			return [int(table[idx]), &""]
	if points < 1:
		return [0x42, &""]
	if points < 20000:
		return [[0x43, 0x44, 0x45, 0x220][clampi(room_size, 0, 3)], &""]
	if points < REWARD0_POINTS:
		return [0x46, &""]
	return [0x47 if points < REWARD1_POINTS else 0x48, &""]


## `mMkRm_ReportChangePlayerRoom`.
func report_change(year: int, month: int, day: int) -> void:
	updated = true
	mark_date = Vector3i(year, month, day)


## `mMkRm_MarkRoom` at game start: the letter to send, or null.
func mark(house: House, main: Room, upper: Room, today: Vector3i, first_job: bool,
		player: String, rng: RandomNumberGenerator) -> MailData:
	if first_job or talk != Talk.NONE or not available():
		return null
	if not member:
		member = true
		mark_date = today
		updated = false
		return _letter(WELCOME, player, {}, &"")
	if mark_date == today:
		return null
	if updated:
		var size: int = PlayerHouse.tier_of(house)
		var result: Dictionary = score_floor(pieces_of(main), size,
			wall_index(main.wall_id if main else &"", "wall_"), wall_index(main.floor_id if main else &"", "floor_"),
			FULL)
		var points: int = int(result["points"])
		var bits: int = int(result["bits"])
		if size == 3 and upper != null:
			var up: Dictionary = score_floor(pieces_of(upper), 1, wall_index(upper.wall_id, "wall_"),
				wall_index(upper.floor_id, "floor_"), UPPER_MODE)
			points += int(up["points"])
			bits |= int(up["bits"])
		mark_date = today
		updated = false
		var pick: Array = decide_letter(points, bits, size, rng)
		if int(pick[0]) == REWARD0_LETTER:
			reward0 = true
		elif int(pick[0]) == REWARD1_LETTER:
			reward1 = true
		var rec: Dictionary = result["base_rec"] if not (result["base_rec"] as Dictionary).is_empty() else result["theme_rec"]
		var free := {
			0: str(points),
			1: _rec_name(rec),
			2: str(result["series"]),
			3: str(today.x),
			4: DialogueCatalog.rom_string(NoticeBoard.STRING_MONTH_START + today.y - 1),
			5: DialogueCatalog.rom_string(NoticeBoard.STRING_DAY_START + today.z - 1),
		}
		return _letter(int(pick[0]), player, free, pick[1])
	if rng.randi_range(0, 9) in [5, 9]:
		var all: int = (1 << HINT_NUM) - 1
		if hint_bits == all:
			hint_bits = 0
		var free_hints: Array[int] = []
		for i: int in HINT_NUM:
			if (hint_bits >> i) & 1 == 0:
				free_hints.append(i)
		if free_hints.is_empty():
			return null
		var hint: int = free_hints[rng.randi_range(0, free_hints.size() - 1)]
		hint_bits |= 1 << hint
		mark_date = today
		updated = false
		return _letter(HINT_BASE + hint, player, {}, &"")
	return null


static func _rec_name(rec: Dictionary) -> String:
	if rec.is_empty() or int(rec.get("index", -1)) < 0:
		return ""
	var id: StringName = FtrCatalog.item_id(int(rec["index"])) if rec["kind"] == "ftr" \
		else FtrCatalog.goods_id(str(rec["kind"]), int(rec["index"]))
	var item: ItemData = ItemCatalog.get_item(id)
	return item.display_name if item != null else ""


static func _letter(no: int, player: String, free: Dictionary, present: StringName) -> MailData:
	var text: Dictionary = MailBank.letter(no, player, free)
	var mail := MailData.new()
	mail.sender_id = &"hra"
	mail.sender_name = "HRA"
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.paper_type = PAPER
	mail.font = MailData.LetterFont.RECV_PRESENT if present != &"" else MailData.LetterFont.RECV
	mail.present_item_id = present
	mail.header = str(text.get("header", ""))
	mail.body = str(text.get("body", ""))
	mail.footer = str(text.get("footer", ""))
	return mail


func to_save() -> Dictionary:
	return {"member": member, "updated": updated, "date": [mark_date.x, mark_date.y, mark_date.z],
		"hints": hint_bits, "reward0": reward0, "reward1": reward1, "talk": talk}


func apply_snapshot(d: Dictionary) -> void:
	member = bool(d.get("member", false))
	updated = bool(d.get("updated", false))
	var date: Array = d.get("date", [0, 0, 0])
	mark_date = Vector3i(int(date[0]), int(date[1]), int(date[2])) if date.size() == 3 else Vector3i.ZERO
	hint_bits = int(d.get("hints", 0))
	reward0 = bool(d.get("reward0", false))
	reward1 = bool(d.get("reward1", false))
	talk = clampi(int(d.get("talk", Talk.NONE)), Talk.NONE, Talk.DUE)


## `mEv_UnSetFirstJob`: the chores are done; Nook will bring up the Academy tomorrow.
func first_job_done() -> void:
	talk = Talk.WAIT


## `mEv_RenewalDataEveryDay`.
func renew_day() -> void:
	if talk == Talk.WAIT:
		talk = Talk.DUE


## `aNSC_start_wait` / `aSHM_happy_academy2_init`: Nook's turn to tell you; once.
func take_nook_talk() -> bool:
	if talk != Talk.DUE:
		return false
	talk = Talk.NONE
	return true
