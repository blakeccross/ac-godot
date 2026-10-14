class_name NoticeBoard
extends RefCounted

## The community board (`m_notice.c`): up to 15 posts, oldest first, each a 192-character
## body and the time it went up. A full board drops its oldest post (`mNtc_notice_write`).
## A new town starts with four handbills — the board's welcome, Nook's HRA recruitment,
## the HRA points guide and how to post (`mNtc_SetInitData`, handbills 0x1E–0x21).
##
## Seasonal notices post themselves (`mNtc_set_auto_nwrite_data`): 43 dated handbills
## (`0x1A4 + id`) from Nook's New Year greeting to the daylight-saving notices, the sports
## fairs and daylight-saving dates moving with the year. On each check every notice whose
## date (from 06:00) passed since the last check is written, at most the latest five,
## dated at 06:00 of their day. `{free0}` is the town, `{free1}` the shop, `{free2}` the
## harvest moon's date and `{free4}` the autumnal equinox's.
##
## Each fishing tourney (June and November Sundays) posts its winner once the day ends at
## 18:00 (`mNtc_get_fishing_day`, handbill 0x242, `FishRecord`), among the same five.
##
## A check that writes nothing seasonal may bring a villager's buried-treasure post
## (`mNtc_check_treasure`, `BuriedTreasure`).

const POST_COUNT := 15
const BODY_LEN := 192
const AUTO_WRITE_MAX := 5
const RENEW_HOUR := 6
const INIT_HANDBILLS: Array[int] = [0x1E, 0x1F, 0x20, 0x21]
const AUTO_HANDBILL_BASE := 0x1A4
## `mString_DAY_START` / `mString_MONTH_START` / the shop names (`0x558 + level`).
const STRING_DAY_START := 0x64E
const STRING_MONTH_START := 0x66D
const STRING_SHOP_START := 0x558
## `auto_nwrite_date_data`: [id, month, day]; month 0 marks the two unused entries.
const AUTO_DATES: Array = [
	[0x00, 1, 1], [0x01, 1, 15], [0x02, 1, 25], [0x03, 2, 1], [0x04, 2, 15], [0x05, 3, 15], [0x06, 3, 11],
	[0x07, 3, 16], [0x08, 3, 20], [0x09, 4, 3], [0x0A, 4, 21], [0x0B, 5, 6], [0x0C, 5, 20], [0x0D, 6, 8],
	[0x0E, 6, 23], [0x0F, 6, 25], [0x10, 7, 1], [0x11, 7, 5], [0x12, 7, 15], [0x13, 7, 25], [0x14, 8, 1],
	[0x15, 8, 30], [0x16, 9, 1], [0x17, 9, 15], [0x18, 9, 13], [0x19, 9, 18], [0x1A, 9, 22], [0x1B, 10, 10],
	[0x1C, 10, 16], [0x1D, 10, 20], [0x1E, 10, 25], [0x1F, 11, 8], [0x20, 11, 10], [0x21, 11, 12],
	[0x22, 11, 23], [0x23, 12, 9], [0x24, 12, 20], [0x25, 12, 25], [0x26, 12, 28], [0x27, 0, 0], [0x28, 0, 0],
	[0x29, 3, 31], [0x2A, 10, 31],
]

## {text: String, year, month, day, hour, minute}
var posts: Array[Dictionary] = []
## `saved_auto_nwrite_time` as y/m/d/h; year 0 until the first check.
var checked := Vector4i.ZERO


## `mNtc_SetInitData`: the four handbills, dated now.
func seed(year: int, month: int, day: int, hour: int, minute: int) -> void:
	posts.clear()
	for no: int in INIT_HANDBILLS:
		posts.append(_post(MailBank.text("mail", no), year, month, day, hour, minute))
	checked = Vector4i(year, month, day, hour)


static func _post(text: String, year: int, month: int, day: int, hour: int, minute: int) -> Dictionary:
	return {"text": text.substr(0, BODY_LEN), "year": year, "month": month, "day": day, "hour": hour,
		"minute": minute}


func count() -> int:
	return posts.size()


## `mNtc_notice_write`.
func write(post: Dictionary) -> void:
	if posts.size() >= POST_COUNT:
		posts.remove_at(0)
	posts.append(post)


## `mNtc_operate_data_list`: this year's date for every notice, sorted.
static func auto_dates(year: int) -> Array:
	var out: Array = []
	for row: Array in AUTO_DATES:
		var id: int = row[0]
		var m: int = row[1]
		var d: int = row[2]
		if m == 0:
			continue
		match id:
			0x06, 0x07, 0x08:
				m = 3
				d = EventDates.vernal_equinox_day(year) + [-10, -5, -1][id - 0x06]
			0x18, 0x19, 0x1A:
				m = 9
				d = EventDates.autumnal_equinox_day(year) + [-10, -5, -1][id - 0x18]
			0x29:
				d = EventDates.last_weekday_day(year, 3, 0)
			0x2A:
				d = EventDates.last_weekday_day(year, 10, 0) - 7
		out.append([id, m, d])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] * 32 + a[2] < b[1] * 32 + b[2])
	return out


static func _stamp(year: int, month: int, day: int, hour: int) -> int:
	return ((year * 13 + month) * 32 + day) * 24 + clampi(hour, 0, 23)


## Posts every notice whose date passed since the last check (the latest five), then
## records now as checked. `fishing` gives a tourney day's winner (`FishRecord.holder`,
## by ordinal); without it no results go up. Returns how many were written.
func auto_write(year: int, month: int, day: int, hour: int, free: Dictionary = {}, fishing: Callable = Callable()) -> int:
	if checked.x == 0:
		checked = Vector4i(year, month, day, hour)
		return 0
	var from: int = _stamp(checked.x, checked.y, checked.z, checked.w)
	var to: int = _stamp(year, month, day, hour)
	## Only the latest five matter, so a long absence looks back at most a year.
	var first_year: int = maxi(checked.x, year - 1)
	checked = Vector4i(year, month, day, hour)
	if to <= from:
		return 0
	var due: Array = []
	for y: int in range(first_year, year + 1):
		for row: Array in auto_dates(y):
			var at: int = _stamp(y, int(row[1]), int(row[2]), RENEW_HOUR)
			if at > from and at <= to:
				due.append([y, row, at])
		if fishing.is_valid():
			for m: int in [6, 11]:
				for d: int in range(1, EventDates.days_in_month(y, m) + 1):
					var end: int = _stamp(y, m, d, FishRecord.END_HOUR)
					if FishRecord.is_tourney_day(y, m, d) and end > from and end <= to:
						due.append([y, [-1, m, d], end])
	due.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) < int(b[2]))
	if due.size() > AUTO_WRITE_MAX:
		due = due.slice(due.size() - AUTO_WRITE_MAX)
	for entry: Array in due:
		var y: int = entry[0]
		var row: Array = entry[1]
		if int(row[0]) < 0:
			var winner: Dictionary = fishing.call(EventDates.ordinal(y, int(row[1]), int(row[2])))
			write(_post(FishRecord.notice_text(y, int(row[1]), int(row[2]), winner), y, int(row[1]), int(row[2]),
				FishRecord.END_HOUR, 0))
			continue
		var slots: Dictionary = free.duplicate()
		slots[2] = day_string(EventDates.harvest_moon(y).x, EventDates.harvest_moon(y).y)
		slots[4] = day_string(9, EventDates.autumnal_equinox_day(y))
		var text: String = MailBank.text("mail", AUTO_HANDBILL_BASE + int(row[0]))
		for key: Variant in slots.keys():
			text = text.replace("{free%d}" % int(key), str(slots[key]))
		write(_post(text, y, int(row[1]), int(row[2]), RENEW_HOUR, 0))
	return due.size()


## `mNtc_make_auto_nwrite_day_string`: "September 21st".
static func day_string(month: int, day: int) -> String:
	var m: String = DialogueCatalog.rom_string(STRING_MONTH_START + clampi(month, 1, 12) - 1)
	var d: String = DialogueCatalog.rom_string(STRING_DAY_START + clampi(day, 1, 31) - 1)
	return ("%s %s" % [m, d]).strip_edges()


## `mNtc_set_auto_nwrite_common_string`: the town and the shop's current name.
static func common_free(town: String, shop_level: int) -> Dictionary:
	return {0: town, 1: DialogueCatalog.rom_string(STRING_SHOP_START + clampi(shop_level, 0, 3))}


func to_save() -> Dictionary:
	return {"posts": posts.duplicate(true), "checked": [checked.x, checked.y, checked.z, checked.w]}


func apply_snapshot(data: Dictionary) -> void:
	posts.clear()
	for p: Variant in data.get("posts", []):
		if p is Dictionary:
			var d: Dictionary = p
			posts.append(_post(str(d.get("text", "")), int(d.get("year", 0)), int(d.get("month", 1)),
				int(d.get("day", 1)), int(d.get("hour", 0)), int(d.get("minute", 0))))
	while posts.size() > POST_COUNT:
		posts.remove_at(0)
	var c: Array = data.get("checked", [0, 0, 0, 0])
	checked = Vector4i(int(c[0]), int(c[1]), int(c[2]), int(c[3])) if c.size() == 4 else Vector4i.ZERO
