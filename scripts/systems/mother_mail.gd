class_name MotherMail
extends RefCounted

## Letters from Mom (`mPr_SendMailFromMother`, `m_private.c`), checked once a day when a game
## starts. The very first check only notes the date. After that, on a new day:
##
## - **Dated letters** (`mPr_SendMotherMailDate`), only on the day itself: the player's
##   birthday (0x184, with a birthday cake), the day whose number matches the month (1/1,
##   2/2 … 12/12: 0x164 + (month − 1) × 2, 10,000 Bells in January, mushrooms on the first
##   October variant), April Fools' (0x180), Mother's Day (0x17C), Father's Day (0x17E,
##   from Dad) and December 24th (0x182, a piece of Nook's furniture). Each has two variants.
## - Otherwise a **20% chance** of an everyday letter (`mPr_SendMotherMailNormal`): one of 56
##   (0x12C on) not sent yet, some with a present. Once all 56 have gone the record is wiped
##   and that one time a seasonal letter for the month goes instead.
##
## The seasonal letters sit on the disc by season and month: spring 0x18C (March–May),
## summer 0x192 (June, July, then eight for August), autumn 0x186 (September–November),
## winter 0x19E (December–February), two per month. (`mPr_GetMotherMailMonthlyData` works
## the number out differently; the disc's texts follow this order.)
##
## The paper is the month's own (`paper_table`), with special ones for the birthday,
## New Year's Day, August 8th and Christmas Eve. Letters go to the mailbox, else the post
## office. `state` is `{"date": ordinal, "normal": bits, "monthly": bits}` (saved).

const NORMAL_COUNT := 56
const MSG_NORMAL := 0x12C
const MSG_MONTH_DAY := 0x164
const MSG_MOTHERS_DAY := 0x17C
const MSG_FATHERS_DAY := 0x17E
const MSG_APRIL_FOOLS := 0x180
const MSG_TOY_DAY := 0x182
const MSG_BIRTHDAY := 0x184
const VARIANTS := 2
## Season start letter and first month: spring, summer, autumn, winter.
const SEASON_MSG: Array[int] = [0x18C, 0x192, 0x186, 0x19E]
const SEASON_FIRST_MONTH: Array[int] = [3, 6, 9, 12]
## August has eight seasonal letters, every other month two.
const AUGUST_LETTERS := 8
## `paper_table` (1-based on the disc).
const PAPER: Array[int] = [13, 49, 32, 12, 62, 14, 19, 11, 59, 46, 47, 17]
const PAPER_BIRTHDAY := 1
const PAPER_NEW_YEAR := 63
const PAPER_AUG_8 := 48
const PAPER_XMAS_EVE := 23
const NORMAL_CHANCE := 20
## Furniture numbers: `FTR_SUM_BDCAKE01`, `FTR_SUM_DOLL02`, `FTR_SUM_PL_DRACAENA`.
const FTR_CAKE := 127
const FTR_PAPA_BEAR := 58
const FTR_DRACAENA := 236
## `december_2_item_table`: aurora knit, winter sweater, go-go shirt, deer shirt, blue check
## shirt, fish knit.
const DECEMBER_SHIRTS: Array[int] = [108, 109, 110, 144, 145, 156]
const MAY_SHIRT := 105
## `mPr_SendMotherMailDate`: the October 10th letter whose present is mushrooms.
const MUSHROOM_LETTER := 18


static func new_state() -> Dictionary:
	return {"date": 0, "normal": 0, "monthly": 0}


## `mPr_GetMotherMailPaperType` (0-based).
static func paper(month: int, day: int, birthday: Vector2i) -> int:
	var p: int = PAPER[clampi(month, 1, 12) - 1]
	if birthday == Vector2i(month, day):
		p = PAPER_BIRTHDAY
	elif month == 1 and day == 1:
		p = PAPER_NEW_YEAR
	elif month == 8 and day == 8:
		p = PAPER_AUG_8
	elif month == 12 and day == 24:
		p = PAPER_XMAS_EVE
	return p - 1


## Mother's Day (second Sunday of May) and Father's Day (third Sunday of June), as the
## event calendar runs them.
static func holiday(year: int, month: int, day: int) -> StringName:
	if month == 5 and day == EventDates.nth_weekday_day(year, 5, 2, 0):
		return &"mothers_day"
	if month == 6 and day == EventDates.nth_weekday_day(year, 6, 3, 0):
		return &"fathers_day"
	return &""


## `mPr_SendMotherMailDate`: {msg, present} for a dated letter today, or {} on an ordinary
## day. `holiday` is `&"mothers_day"`, `&"fathers_day"` or `&""`.
static func dated(month: int, day: int, birthday: Vector2i, holiday: StringName, rng: RandomNumberGenerator) -> Dictionary:
	if birthday == Vector2i(month, day):
		return {"msg": MSG_BIRTHDAY + rng.randi_range(0, VARIANTS - 1), "present": FtrCatalog.item_id(FTR_CAKE)}
	if month == day:
		var n: int = (month - 1) * VARIANTS + rng.randi_range(0, VARIANTS - 1)
		var present: StringName = &""
		if month == 1:
			present = &"money_10000"
		elif n == MUSHROOM_LETTER:
			present = &"mushroom"
		return {"msg": MSG_MONTH_DAY + n, "present": present}
	var msg: int = -1
	var gift: StringName = &""
	if month == 4 and day == 1:
		msg = MSG_APRIL_FOOLS
	elif holiday == &"mothers_day":
		msg = MSG_MOTHERS_DAY
	elif holiday == &"fathers_day":
		msg = MSG_FATHERS_DAY
	elif month == 12 and day == 24:
		msg = MSG_TOY_DAY
		var picks: Array[StringName] = ShopGoods.select("ftr", 1, -1, _goods_power(), rng)
		gift = picks[0] if not picks.is_empty() else &""
	if msg < 0:
		return {}
	return {"msg": msg + rng.randi_range(0, VARIANTS - 1), "present": gift}


static func _goods_power() -> int:
	return Game.goods_power_now() if Game != null else 0


static func _bit(bits: int, i: int) -> bool:
	return (bits >> i) & 1 == 1


## Unsent everyday letters.
static func normal_left(state: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var bits: int = int(state.get("normal", 0))
	for i: int in NORMAL_COUNT:
		if not _bit(bits, i):
			out.append(i)
	return out


static func monthly_count(month: int) -> int:
	return AUGUST_LETTERS if month == 8 else VARIANTS


## Seasonal letter slots for `month` not sent since the last wipe.
static func monthly_left(state: Dictionary, month: int) -> Array[int]:
	var out: Array[int] = []
	var bits: int = int(state.get("monthly", 0))
	for i: int in monthly_count(month):
		if not _bit(bits, monthly_bit(month, i)):
			out.append(i)
	return out


## Bit for a seasonal letter: two per month, August's eight after the other months.
static func monthly_bit(month: int, idx: int) -> int:
	return 24 + idx if month == 8 else (month - 1) * VARIANTS + idx


## Message number of seasonal letter `idx` for `month`.
static func monthly_msg(month: int, idx: int) -> int:
	var season: int = 0
	for s: int in range(SEASON_FIRST_MONTH.size() - 1, -1, -1):
		if month >= SEASON_FIRST_MONTH[s]:
			season = s
			break
	if month < SEASON_FIRST_MONTH[0]:
		season = 3
	var into: int = posmod(month - SEASON_FIRST_MONTH[season], 12)
	return SEASON_MSG[season] + into * VARIANTS + idx


static func monthly_present(month: int, idx: int, rng: RandomNumberGenerator) -> StringName:
	if month == 5 and idx == 1:
		return &"shirt_%03d" % MAY_SHIRT
	if month == 12:
		if idx == 0:
			return &"apple"
		return &"shirt_%03d" % DECEMBER_SHIRTS[rng.randi_range(0, DECEMBER_SHIRTS.size() - 1)]
	if month == 11:
		return &"mushroom"
	return &""


## `mPr_GetMotherMailNormalData`'s presents.
static func normal_present(idx: int, rng: RandomNumberGenerator) -> StringName:
	match idx:
		1, 16:
			var picks: Array[StringName] = ShopGoods.select("cloth", 1, -1, _goods_power(), rng)
			return picks[0] if not picks.is_empty() else &""
		3, 21, 22, 47:
			return VillagerQuests.other_fruit(rng)
		12:
			return &"money_1000"
		37:
			return FtrCatalog.item_id(FTR_PAPA_BEAR)
		38:
			return FtrCatalog.item_id(FTR_DRACAENA)
		40:
			var umbrellas: Array[StringName] = ShopGoods.umbrella_pool()
			return umbrellas[rng.randi_range(0, umbrellas.size() - 1)] if not umbrellas.is_empty() else &""
	return &""


## `mPr_SendMotherMailNormal`: {msg, present, mark: [key, bit]} or {} (no letter today).
static func everyday(state: Dictionary, month: int, rng: RandomNumberGenerator) -> Dictionary:
	if rng.randi_range(0, 99) >= NORMAL_CHANCE:
		return {}
	var left: Array[int] = normal_left(state)
	if left.is_empty():
		state["normal"] = 0
		state["monthly"] = 0
		var slots: Array[int] = monthly_left(state, month)
		var idx: int = slots[rng.randi_range(0, slots.size() - 1)]
		return {
			"msg": monthly_msg(month, idx), "present": monthly_present(month, idx, rng),
			"mark": ["monthly", monthly_bit(month, idx)],
		}
	var n: int = left[rng.randi_range(0, left.size() - 1)]
	return {"msg": MSG_NORMAL + n, "present": normal_present(n, rng), "mark": ["normal", n]}


## The letter Mom sends for `state` on `ordinal` (`mPr_SendMailFromMother`), already marked
## as sent once `deliver` takes it. Returns the message number, or -1.
static func check(
	state: Dictionary, ordinal: int, birthday: Vector2i, holiday: StringName, player: String,
	rng: RandomNumberGenerator, deliver: Callable
) -> int:
	var last: int = int(state.get("date", 0))
	if last == ordinal:
		return -1
	state["date"] = ordinal
	if last <= 0:
		return -1
	var date: Vector3i = EventDates.from_ordinal(ordinal)
	var pick: Dictionary = dated(date.y, date.z, birthday, holiday, rng)
	if pick.is_empty():
		pick = everyday(state, date.y, rng)
	if pick.is_empty():
		return -1
	var mail: MailData = letter(int(pick["msg"]), StringName(pick.get("present", &"")), paper(date.y, date.z, birthday), player)
	if mail == null or not bool(deliver.call(mail)):
		return -1
	if pick.has("mark"):
		var mark: Array = pick["mark"]
		state[mark[0]] = int(state.get(mark[0], 0)) | (1 << int(mark[1]))
	return int(pick["msg"])


## `mPr_GetMotherMail`.
static func letter(msg: int, present: StringName, paper_type: int, player: String) -> MailData:
	if not MailBank.has_bank():
		return null
	var text: Dictionary = MailBank.letter(msg, player, {0: player})
	var mail := MailData.new()
	mail.header = text["header"]
	mail.body = text["body"]
	mail.footer = text["footer"]
	mail.sender_id = &"mom"
	mail.sender_name = "Mom"
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = player
	mail.paper_type = paper_type
	mail.present_item_id = present if ItemCatalog.get_item(present) != null else &""
	mail.font = MailData.LetterFont.RECV_PRESENT if mail.present_item_id != &"" else MailData.LetterFont.RECV
	return mail
