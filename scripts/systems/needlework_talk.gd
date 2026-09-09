class_name NeedleworkTalk
extends RefCounted

## Message-id tables for the Able Sisters talk flow, ported from
## `src/actor/npc/ac_npc_needlework_talk.c_inc`. Text lives in the imported ROM
## message banks — fetch a line with `DialogueCatalog.conversation(&"msg_%d" % id)`.

const SISTER_NOW_NUM := 3
const STORY_BASE := 0x3012

## aNNW_message_table[24 * 3] — 0xFF = end of this story row.
const MESSAGE_TABLE: Array = [
	0x00, 0xFF, 0xFF,  0x01, 0xFF, 0xFF,  0x02, 0x20, 0x21,  0x03, 0x22, 0x23,
	0x04, 0xFF, 0xFF,  0x05, 0xFF, 0xFF,  0x06, 0xFF, 0xFF,  0x07, 0x24, 0xFF,
	0x08, 0xFF, 0xFF,  0x09, 0x25, 0x26,  0x0A, 0xFF, 0xFF,  0x0B, 0xFF, 0xFF,
	0x0C, 0xFF, 0xFF,  0x0D, 0x27, 0x28,  0x0E, 0xFF, 0xFF,  0x0F, 0x29, 0x2A,
	0x10, 0xFF, 0xFF,  0x11, 0x2B, 0x2C,  0x13, 0xFF, 0xFF,  0x14, 0xFF, 0xFF,
	0x15, 0xFF, 0xFF,  0x16, 0xFF, 0xFF,  0x17, 0xFF, 0xFF,  0x18, 0xFF, 0xFF,
]
const STORY_FIRST_TABLE: Array = [5, 9, 13, 17]
const STORY_OTHER_TABLE: Array = [6, 10, 14, 18]

## Mabel first-talk / repeat greetings.
const GREETING_FIRST := 0x2FD4
const GREETING_REPEAT := 0x3005
## aNNW_set_force_talk_info force_msg_table.
const FORCE_GREETINGS: Array = [0x2FD1, 0x2FD2, 0x2FD3, 0x2FF2, 0x2FF3, 0x3034, 0x3035]

## Trade-flow result lines.
const MSG_TRADE_EXCHANGE := 0x2FFA
const MSG_TRADE_PUT_ON_MANNEQUIN := 0x2FF8
const MSG_TRADE_BUY_DESIGN := 0x2FF9
const MSG_TRADE_WRONG_ITEM := 0x2FF5
const MSG_DESIGN_NO_MONEY := 0x2FE7
const MSG_DESIGN_SAVED := 0x2FEA
const MSG_DESIGN_NOT_BLANK := 0x2FE9
const MSG_DESIGN_NAMED := 0x2FEB
const MSG_GBA_NOT_CONNECTED := 0x3008

const DESIGN_PRICE := 350  ## aNNW_DESIGN_PRICE


## Pick the sister-story row for this talk (`aNNW_get_make_sister_message`).
## `days` = DesignBook.sable_days, `first_of_day` = has the counter not advanced yet
## for today (i.e. this talk will advance it).
static func pick_story_row(days: int, first_of_day: bool, rng: RandomNumberGenerator) -> int:
	var d: int = days + (1 if first_of_day else 0)
	if d < 4:
		return rng.randi_range(0, 4)
	if d >= 8:
		return 21 + rng.randi_range(0, 2)
	var slot: int = clampi(d - 4, 0, 3)
	if first_of_day:
		return int(STORY_FIRST_TABLE[slot])
	return int(STORY_OTHER_TABLE[slot]) + rng.randi_range(0, 2)


## Full sequence of message ids for one sister-story talk.
static func story_line_ids(story_row: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	var row: int = clampi(story_row, 0, 23)
	for now in SISTER_NOW_NUM:
		var v: int = int(MESSAGE_TABLE[row * SISTER_NOW_NUM + now])
		if v == 0xFF:
			break
		out.append(STORY_BASE + v)
	return out


static func force_greeting(rng: RandomNumberGenerator) -> int:
	return int(FORCE_GREETINGS[rng.randi_range(0, FORCE_GREETINGS.size() - 1)])


## `DialogueData` for a single ROM message id, or null.
static func line(msg_id: int) -> DialogueData:
	return DialogueCatalog.conversation(StringName("msg_%d" % msg_id))
