class_name VillagerTalk
extends RefCounted

## Greeting pick + substitutions. Not `m_msg` banks. UI comes later.

const FALLBACK := "Hello!"


static func day_key() -> String:
	return "%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]


static func greeting(villager: VillagerData, state: VillagerState) -> String:
	var raw: String = _raw_line(villager, state, Clock.time_of_day())
	return substitute(raw, villager)


static func substitute(line: String, villager: VillagerData) -> String:
	var out: String = line
	if villager != null:
		out = out.replace("{name}", villager.display_name)
		out = out.replace("{catchphrase}", villager.catchphrase)
		out = out.replace("{species}", String(villager.species))
	return out


static func _raw_line(
	villager: VillagerData, state: VillagerState, tod: ClockService.TimeOfDay
) -> String:
	var dialogue: DialogueData = villager.dialogue if villager != null else null
	if state != null and state.talked_on(day_key()) and dialogue != null:
		if dialogue.already_talked != "":
			return dialogue.already_talked
	if dialogue != null:
		var timed: String = dialogue.line_for_time(tod)
		if timed != "":
			return timed
		if dialogue.lines.size() > 0:
			return dialogue.lines[0]
	if villager != null and villager.catchphrase != "":
		return villager.catchphrase
	return FALLBACK
