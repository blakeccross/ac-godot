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
	var phrase: String = catchphrase_of(villager, state)
	if phrase != "":
		return phrase
	return FALLBACK


## `Animal_c.catchphrase`: the player's edit, else the villager's default.
static func catchphrase_of(villager: VillagerData, state: VillagerState) -> String:
	if state != null and state.catchphrase != "":
		return state.catchphrase
	return villager.default_catchphrase() if villager != null else ""


static func conversation(villager: VillagerData, state: VillagerState) -> DialogueData:
	if villager != null and villager.dialogue != null:
		return villager.dialogue
	return DialogueGreeting.conversation(villager, state)


## The quest manager for a talk with a town villager, or null when the talk is a scripted
## one (authored dialogue, the first job, or someone who doesn't live here).
static func manager(villager: VillagerData, state: VillagerState, ctx: DialogueContext) -> VillagerTalkManager:
	if villager == null or villager.dialogue != null or Game == null or Game.residents == null:
		return null
	## During the first job villagers only take quest talk once Nook says to ask around
	## (`mEv_SAVED_FJOPENQUEST`); the rest of the job is scripted.
	if Game.first_job != null and Game.first_job.is_active() and not Game.first_job.open_quest:
		return null
	var slot: int = Game.residents.slot_of(villager.id)
	if slot < 0:
		return null
	var m := VillagerTalkManager.new(villager, state, ctx)
	m.slot = slot
	m.hint_count_get = func() -> int: return Game.first_job_hint_count
	m.hint_count_set = func(v: int) -> void: Game.first_job_hint_count = v
	m.show_letter = func(letter: Dictionary) -> void: _show_letter(villager, letter)
	m.send_mail = Game.deliver_to_mailbox
	m.field_counts = Game.field_counts
	if state != null:
		## `mNpc_GetOverImpatient` for the greeting.
		state.patience = Game.npc_talk_info.patience(slot, m.looks) as VillagerState.Patience
	return m


## `aQMgr_talk_normal_open_letter`: the letter the topic talked about, on the read board.
static func _show_letter(villager: VillagerData, letter: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var reader := tree.get_first_node_in_group("letter_reader_ui") as LetterReaderOverlay
	if reader == null or reader.is_open():
		return
	var mail := MailData.new()
	mail.sender_id = villager.id if villager != null else &""
	mail.sender_name = villager.display_name if villager != null else ""
	mail.sender_type = MailData.NameType.NPC
	mail.font = MailData.LetterFont.RECV
	mail.header = str(letter.get("header", ""))
	mail.body = str(letter.get("body", ""))
	mail.footer = str(letter.get("footer", ""))
	mail.paper_type = int(letter.get("paper_type", 0))
	reader.open(mail)


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
