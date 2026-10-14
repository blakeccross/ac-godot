class_name AprilFools
extends RefCounted

## April Fools' Day for the town's special NPCs (`ac_aprilfool_control`). The first time a
## resident talks to each of them that day, they try a trick on them instead of their usual
## talk (`aAPC_get_msg_num_proc`); after that they're themselves again. Visitors from
## another town get nothing (`mLd_PlayerManKindCheck`). The villagers' own April Fools'
## hello is in `DialogueGreeting`.
##
## `Game.events.area("aprilfools_day")`: `{day, talked: {player slot: [npc, …]}}`.

const EVENT := &"aprilfools_day"
## `msg_num_table` by NPC.
const MSG: Dictionary = {
	&"porter": 0x3BB5, &"tom_nook": 0x3BAC, &"blathers": 0x3BB0, &"mable": 0x3BB1,
	&"sable": 0x3BB2, &"copper": 0x3BB3, &"booker": 0x3BB4, &"pelly": 0x3BAE,
	&"phyllis": 0x3BAF, &"pete": 0x3BAD, &"kapp_n": 0x3BB6,
}


static func _talked() -> Array:
	var area: Dictionary = Game.events.area(EVENT)
	var today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
	if int(area.get("day", -1)) != today:
		area["day"] = today
		area["talked"] = {}
	var talked: Dictionary = area["talked"]
	var slot: String = str(Game.roster.current if Game.roster != null else 0)
	if not talked.has(slot):
		talked[slot] = []
	return talked[slot]


## `aAPC_talk_chk_proc` == FALSE: this NPC still has a trick for the player today.
static func pending(npc: StringName) -> bool:
	if Game == null or Game.events == null or Game.foreigner or not MSG.has(npc):
		return false
	if not Game.events.is_active(EVENT):
		return false
	return not _talked().has(String(npc))


## `aAPC_get_msg_num_proc(npc, TRUE)`: the trick, marked as played; -1 when there's none.
static func take(npc: StringName) -> int:
	if not pending(npc):
		return -1
	_talked().append(String(npc))
	return int(MSG[npc])


## The trick as a conversation, marked as played; null when there's none.
static func conversation(npc: StringName) -> DialogueData:
	if not pending(npc):
		return null
	var data: DialogueData = DialogueCatalog.conversation(StringName("msg_%d" % int(MSG[npc])))
	if data != null:
		take(npc)
	return data
