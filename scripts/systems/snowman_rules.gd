class_name SnowmanRules
extends RefCounted

## Snowman rules without the scene (`ac_snowman`, `ac_psnowman`, `m_snowman`).
##
## Snowman season (Dec 25 – Feb 17, `snowman_start`) puts two snowballs in town, a body
## part and a head part (`ETC_SNOWMAN_BALL_A` / `B`). A ball grows with the distance it rolls
## on grass (snow) and shrinks on anything else (`aSMAN_calc_scale`, full at 6400 GX).
## Rolled into each other while both are past a fifth of full size, the faster one jumps on
## top as the head; the snowman is graded on head ÷ body against 0.85 (`aSMAN_decide_scale_
## result`), and a perfect one mails a piece of snowman furniture. Up to three stand at once
## (`mSN_SAVE_COUNT`); each lasts three days of winter, shrinking to 0.8× every day
## (`mSN_MeltSnowman`). No new balls appear between building one and 6 AM the next day
## (`mEv_snowman_born_check`).

const MOVE_DIST_MAX := 6400.0
const SAVE_COUNT := 3
const PART_BODY := 0
const PART_HEAD := 1
## `normalized_scale` past which a ball can be pushed and combined.
const PUSH_MIN := 0.2
const IDEAL_RATIO := 0.85
enum Result { PERFECT, GOOD, OK, BAD }
## `aSMAN_set_talk_info_combine_head_init` (`MSG_2197`…): three lines per result.
const COMBINE_MSG: Array[int] = [2197, 2200, 2203, 2206]
## `MSG_2209 + ((snowman_msg_id + idx) % 3) + score * 3`.
const SNOWMAN_MSG := 2209
## `aSMAN_GetSnowmanPresentMail` `snow_item_table`: ten pieces (catalog 981–990), then
## carpet and wallpaper 25. The handbill is `0x202 + index`.
const PRESENT_FTR_FIRST := 981
const PRESENT_COUNT := 12
const PRESENT_MAIL := 0x202
## `mEv_snowman_born_check`: the "built" window closes at 5 AM.
const BORN_END_HOUR := 5
const MELT := 0.8
## 1 GX in metres (`PlayerLocomotion.UNIT_METERS`).
const GX := 0.05


## `normalized_scale * 20 + 10`: the ball's radius in GX.
static func radius_gx(n: float) -> float:
	return n * 20.0 + 10.0


static func radius_m(n: float) -> float:
	return radius_gx(n) * GX


## `actor.scale`: 0.01 – 0.03.
static func actor_scale(n: float) -> float:
	return minf(n * 0.02 + 0.01, 0.03)


static func normalized(move_dist: float) -> float:
	return clampf(move_dist, 0.0, MOVE_DIST_MAX) / MOVE_DIST_MAX


## `aSMAN_calc_scale` for one tick: rolled distance grows on snow, wears off elsewhere.
static func roll(move_dist: float, speed: float, on_snow: bool) -> float:
	var d: float = move_dist + (speed if on_snow else -speed * 0.75)
	return clampf(d, 0.0, MOVE_DIST_MAX)


## `aSMAN_decide_scale_result` (actor scales of head and body).
static func result(head_scale: float, body_scale: float) -> int:
	if body_scale <= 0.0:
		return Result.BAD
	var off: float = absf(head_scale / body_scale - IDEAL_RATIO)
	if off <= 0.05:
		return Result.PERFECT
	if off <= 0.15:
		return Result.GOOD
	if off <= 0.25:
		return Result.OK
	return Result.BAD


static func can_combine(part_a: int, n_a: float, part_b: int, n_b: float) -> bool:
	return part_a != part_b and n_a > PUSH_MIN and n_b > PUSH_MIN


static func combine_msg(res: int, rng: RandomNumberGenerator) -> int:
	return COMBINE_MSG[clampi(res, 0, 3)] + rng.randi_range(0, 2)


static func snowman_msg(msg_id: int, slot: int, score: int) -> int:
	return SNOWMAN_MSG + posmod(msg_id + slot, SAVE_COUNT) + clampi(score, 0, 3) * 3


## `mSN_check_life` / `mSN_MeltSnowman`: `entry` {head, body, age}. False when it melts away.
static func melt(entry: Dictionary, days: int, winter: bool) -> bool:
	if days <= 0:
		return true
	if not winter or int(entry.get("age", 0)) + days >= SAVE_COUNT:
		return false
	entry["age"] = int(entry.get("age", 0)) + days
	for _i: int in days:
		entry["head"] = float(entry.get("head", 0.0)) * MELT
		entry["body"] = float(entry.get("body", 0.0)) * MELT
	return true


## `mEv_snowman_born_check`: may new balls appear? `built_minute`: when the last snowman was
## made (`Clock.absolute_minute`, −1 never). The block lasts until 5:59 that morning, or the
## next morning when it was built at 6 AM or later.
static func balls_allowed(built_minute: int, now_minute: int) -> bool:
	if built_minute < 0 or now_minute < built_minute:
		return true
	var built_day: int = floori(float(built_minute) / 1440.0)
	var built_hour: int = (built_minute % 1440) / 60
	var end_day: int = built_day + (1 if built_hour >= 6 else 0)
	var end_minute: int = end_day * 1440 + BORN_END_HOUR * 60 + 59
	return now_minute > end_minute


## The gift for a perfect snowman: one of the twelve, re-rolled once if already collected.
static func present(rng: RandomNumberGenerator, collected: Callable = Callable()) -> Dictionary:
	var pick: int = rng.randi_range(0, PRESENT_COUNT - 1)
	if collected.is_valid() and bool(collected.call(present_id(pick))):
		pick = rng.randi_range(0, PRESENT_COUNT - 1)
	return {"index": pick, "id": present_id(pick), "mail": PRESENT_MAIL + pick}


static func present_id(index: int) -> StringName:
	if index < 10:
		return FtrCatalog.item_id(PRESENT_FTR_FIRST + index)
	if index == 10:
		return FtrCatalog.goods_id("carpet", 25)
	return FtrCatalog.goods_id("wall", 25)


## First free snowman slot (`mSN_get_free_space`), or −1.
static func free_slot(snowmen: Array) -> int:
	for i: int in SAVE_COUNT:
		if i >= snowmen.size() or snowmen[i] == null or (snowmen[i] as Dictionary).is_empty():
			return i
	return -1
