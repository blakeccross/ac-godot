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

## Trend tiers (`aNNW_set_trend_cloth_message` / `_umbrella_message`), by worn count
## 0 / 1 / <5 / >=5.
const MSG_TREND_CLOTH: Array = [0x2FDC, 0x2FDB, 0x2FDA, 0x2FD9]
const MSG_TREND_UMBRELLA: Array = [0x2FE0, 0x2FDF, 0x2FDE, 0x2FDD]


static func trend_tier(count: int) -> int:
	if count <= 0:
		return 0
	if count == 1:
		return 1
	if count < 5:
		return 2
	return 3


## Plain-English trend line for a design and its town wear count.
static func trend_line(design_name: String, count: int, is_umbrella: bool) -> String:
	var thing := "umbrella print" if is_umbrella else "shirt"
	match trend_tier(count):
		0:
			return "Honestly? No %s design has really caught on around town lately." % thing
		1:
			return "Someone's been seen in the \"%s\" %s — it's just starting to spread!" % [design_name, thing]
		2:
			return "The \"%s\" %s is turning heads — a few folks are wearing it now." % [design_name, thing]
		_:
			return "\"%s\" is THE %s this season. Practically everyone's in it!" % [design_name, thing]


## Trade result line (`aNNW_talk_trade_close*` msg swap: 0x2FF8 / 0x2FF9 / 0x2FFA).
static func trade_result_line(kind: String) -> String:
	match kind:
		"display":
			return "Wow! That's so nice!\nAnd who knows? Maybe it'll\nbe the new must-have style\nnext season!"
		"buy":
			return "Isn't it great when you\nfinally get a pattern that\nreally speaks to you?\nIt's like...coming home."
		"exchange":
			return "Wow! Cool! I hope this new\npattern really catches on!"
		_:
			return "Oh, I see."


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


# --- authored text ------------------------------------------------------------
# The ROM message banks aren't in the repo; these stand in for the ids above when
# `DialogueCatalog` has no generated text. Wording is the port's own.

## 0x2FD4 (`aNNW_TALK_WHAT_HAPPEN_FIRST`, before "What's this?" was ever picked) and
## 0x3005 (`aNNW_TALK_WHAT_HAPPEN`) lead into the same 6-way menu.
const TEXT_MENU_FIRST := "Oh, hi! Is this your first\ntime designing? If you're not\nsure, just ask \"What's this?\""
const TEXT_MENU := "Ohhh, yes?\nWhat do you need?"
## `aNNW_TALK_WHAT_HAPPEN` lead after a sub-flow bounces back to the menu.
const TEXT_MENU_AGAIN := "Is there anything else\nI can do for you?"
## 0x2FD3 — force talk when the player faces the exit (`aNNW_THINK_10`).
const TEXT_BYE := "Thanks for stopping by!\nCome back and see us soon!"
## 0x2FE9 — the design list or the editor was closed without a new design.
const TEXT_DESIGN_CANCEL := "Oh, you changed your mind?\nThat's OK! No charge."
## 0x2FEA — the editor saved; the name entry follows.
const TEXT_DESIGN_SAVED := "Oh, that's lovely! Now,\nwhat would you like to\ncall it?"
## 0x2FEB — named and paid for.
const TEXT_DESIGN_NAMED := "\"%s\"! What a great name.\nThat'll be 350 Bells.\nThanks so much!"
## 0x2FE7 — can't afford the 350 Bells.
const TEXT_NO_MONEY := "Oh, no! %s...\nYou don't have enough money!\nDid you leave your cash in\nanother outfit or something?"
## 0x2FF0 — back from the design album.
const TEXT_ALBUM_DONE := "All done? Keep your designs\nsafe and sound in there."
## 0x2FF5 — the trade list was closed without a pick.
const TEXT_TRADE_CANCEL := "Oh? Never mind, then."
## 0x3008 — the GBA branches: no Game Boy Advance is linked.
const TEXT_NO_GBA := "Hmm... I don't see a\nGame Boy Advance connected.\nMaybe another time!"

## `aNNW_TALK_LISTEN_SISTER*` — Mabel explains the shop, turns to Sable for one line
## (`npc_id` swapped to NEEDLEWORK1), then wraps up.
const LISTEN_LINES: Array = [
	["Mabel", "OK! Here at Able Sisters,\nyou can make your very own\ndesigns for 350 Bells each."],
	["Mabel", "Wear one as your shirt\nwhenever you like. You can\nkeep eight at a time."],
	["Mabel", "And if you're proud of one,\nput it on a mannequin or an\numbrella stand here in the shop!"],
	["Sable", "...Folks around town notice\nwhat's on display. Sometimes\nthey start wearing it too."],
	["Mabel", "Right, sis! So check in with\n\"Any suggestions?\" to see\nwhat's catching on!"],
]

## Sister-story rows (`aNNW_message_table`), speakers Sable / Mabel / Sable by `sister_now`.
## <4 days: small talk; 4-7: the first-of-day chapter (5/9/13/17) or its follow-ups;
## >=8: at ease.
const STORY_TEXT: Dictionary = {
	0: ["...Oh. Hello."],
	1: ["...Mm. The needle's being\nfussy today."],
	2: ["...Are you looking for Mabel?", "Sis, it's a customer! Say hi!", "...I did say hello."],
	3: ["...", "Don't mind her, she's just\nshy with new faces!", "...Mabel."],
	4: ["...This hem won't finish itself."],
	5: ["...You came back again.\nMost people only talk to Mabel."],
	6: ["...The thread for this one\ncame all the way from the city."],
	7: ["...Mabel picks the colors.\nI just follow along.", "That's not true! Her stitching\nis the best in the valley!"],
	8: ["...Mm. It's quieter in the\nmornings. I like that."],
	9: ["...When we were small, our\nmother sewed every night.", "We'd fall asleep to the\nsound of her machine.", "...This was her machine."],
	10: ["...I've been fixing this\nmachine for years. It's old,\nbut it still hums."],
	11: ["...Mabel was always the one\nwho talked to people."],
	12: ["...Do you sew? ...No?\nThat's all right."],
	13: ["...After Mother was gone, we\nkept the shop going together.", "Sable did all the sewing.\nI handled...everything else!", "...She still does."],
	14: ["...Some days I wonder if\nthe shop was a good idea."],
	15: ["...We almost closed once.", "Business was slow, and I\nwas so worried...", "...We made it, though."],
	16: ["...Your visits make\nthe days go faster."],
	17: ["...I don't say this much, but\nI'm glad you keep coming.", "See, sis? I told you they're\nnice!", "...Yes. You did."],
	18: ["...I used to dream of making\nclothes for a big city shop."],
	19: ["...Maybe someday. For now,\nthis little shop is enough."],
	20: ["...Thank you for listening\nto an old hedgehog ramble."],
	21: ["Oh, it's you. Come in, come in.\nI saved you a spot by the\nmachine."],
	22: ["Welcome back. ...Mabel's been\nhumming all morning. I think\nshe's happy you visit."],
	23: ["There you are. The shop feels\nbrighter when you stop by."],
}


## Speaker for part `now` of a sister story: Sable opens, Mabel chimes in
## (`aNNW_THINK_AINOTE` → force talk 5), Sable closes (`AINOTE3` → force talk 6).
static func story_speaker(now: int) -> String:
	return "Mabel" if now == 1 else "Sable"


## Readable text for message `msg_id` at part `now` of `story_row`: the ROM line when the
## bank is present and not a bare ellipsis, else `STORY_TEXT`.
static func story_text(story_row: int, now: int, msg_id: int = -1) -> String:
	if msg_id >= 0:
		var data := line(msg_id)
		if data != null:
			data.ensure_loaded()
			var txt := str(data.node(data.start).get("text", "")).strip_edges()
			if not txt.replace(".", "").replace("…", "").strip_edges().is_empty():
				return txt
	var parts: Array = STORY_TEXT.get(clampi(story_row, 0, 23), [])
	if now >= 0 and now < parts.size():
		return str(parts[now])
	return "..."


## `aNNW_ane_3`: the story-9 ending has Sable turn to the player for her last line.
const STORY_TURN_TO_PLAYER := 9
## `aNNW_talk_init`: Sable only looks up from the machine once `nw_visitor.days >= 5`.
const SABLE_TURN_DAYS := 5
