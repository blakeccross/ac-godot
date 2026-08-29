class_name VillagerTalk
extends RefCounted

## Greeting pick + substitutions via `DialogueRunner`. UI is `dialogue_overlay`.

const FALLBACK := "Hello!"


static func day_key() -> String:
	return "%04d-%02d-%02d" % [Clock.year, Clock.month, Clock.day]


static func greeting(villager: VillagerData, state: VillagerState) -> String:
	var runner: DialogueRunner = begin(villager, state)
	if runner != null and runner.line != "":
		return runner.line
	if villager != null and villager.catchphrase != "":
		return villager.catchphrase
	return FALLBACK


static func conversation(villager: VillagerData, state: VillagerState) -> DialogueData:
	if villager != null and villager.dialogue != null:
		return villager.dialogue
	return DialogueGreeting.conversation(villager, state)


static func begin(villager: VillagerData, state: VillagerState) -> DialogueRunner:
	var data: DialogueData = conversation(villager, state)
	var ctx: DialogueContext = DialogueContext.from_game(villager, state)
	var runner := DialogueRunner.new()
	runner.start(data, ctx, state)
	return runner


static func substitute(line: String, villager: VillagerData) -> String:
	var ctx := DialogueContext.new()
	ctx.player_name = Game.player_name
	ctx.town_name = Game.town_name
	if villager != null:
		ctx.speaker_name = villager.display_name
		ctx.catchphrase = villager.catchphrase
		ctx.species = String(villager.species)
	return ctx.substitute(line)
