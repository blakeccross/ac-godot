class_name DialogueRunner
extends RefCounted

## Walks a `DialogueData` graph. Not `m_msg` banks. UI types the current line.

signal finished
signal line_shown(text: String)
signal choices_shown(options: Array)
signal event_fired(event: Dictionary)

var conversation: DialogueData
var context: DialogueContext
var node_id: StringName = &""
var line: String = ""
var choices: Array[Dictionary] = []
var waiting_choice: bool = false
var done: bool = false
var last_choice_index: int = -1
var events_this_step: Array[Dictionary] = []

var _state: VillagerState


func start(
	data: DialogueData, ctx: DialogueContext, villager_state: VillagerState = null
) -> void:
	conversation = data
	context = ctx if ctx != null else DialogueContext.new()
	_state = villager_state
	done = false
	waiting_choice = false
	last_choice_index = -1
	line = ""
	choices.clear()
	if conversation == null:
		done = true
		finished.emit()
		return
	conversation.ensure_loaded()
	_goto(conversation.start)


func advance() -> void:
	if done or waiting_choice:
		return
	var rec: Dictionary = _current()
	var next_id := StringName(str(rec.get("next", "")))
	if next_id == &"":
		_finish()
		return
	_goto(next_id)


func choose(index: int) -> void:
	if not waiting_choice or index < 0 or index >= choices.size():
		return
	last_choice_index = index
	var opt: Dictionary = choices[index]
	_fire_list(opt.get("events", []))
	waiting_choice = false
	choices.clear()
	var next_id := StringName(str(opt.get("goto", "")))
	if next_id == &"":
		_finish()
		return
	_goto(next_id)


func current_kind() -> StringName:
	return StringName(str(_current().get("type", "")))


func _goto(to: StringName) -> void:
	if to == &"":
		_finish()
		return
	if conversation == null or not conversation.has_node(to):
		var other: DialogueData = DialogueCatalog.conversation(to)
		if other != null and other != conversation:
			conversation = other
			conversation.ensure_loaded()
			_goto(conversation.start if to == conversation.id else to)
			return
		if conversation == null or not conversation.has_node(to):
			_finish()
			return
	node_id = to
	_settle()


func _settle() -> void:
	var guard := 0
	while not done and guard < 64:
		guard += 1
		var rec: Dictionary = _current()
		var kind := StringName(str(rec.get("type", KIND_LINE)))
		if rec.has("when") and kind != DialogueData.KIND_BRANCH:
			if not DialogueCondition.matches(rec.get("when"), context):
				var skip := StringName(str(rec.get("else", rec.get("next", ""))))
				if skip == &"" or skip == node_id:
					_finish()
					return
				if conversation.has_node(skip):
					node_id = skip
					continue
				_goto(skip)
				return
		match kind:
			DialogueData.KIND_BRANCH:
				var dest: StringName = _pick_branch(rec)
				if dest == &"":
					_finish()
					return
				if dest == node_id:
					_finish()
					return
				if conversation.has_node(dest):
					node_id = dest
					continue
				_goto(dest)
				return
			DialogueData.KIND_RANDOM:
				var dest: StringName = _pick_random(rec)
				if dest == &"":
					_finish()
					return
				if conversation.has_node(dest):
					node_id = dest
					continue
				_goto(dest)
				return
			DialogueData.KIND_EVENT:
				_fire_list(rec.get("events", []))
				var next_id := StringName(str(rec.get("next", "")))
				if next_id == &"":
					_finish()
					return
				if conversation.has_node(next_id):
					node_id = next_id
					continue
				_goto(next_id)
				return
			DialogueData.KIND_CHOICE:
				_enter_choice(rec)
				return
			_:
				_enter_line(rec)
				return
	_finish()


func _enter_line(rec: Dictionary) -> void:
	waiting_choice = false
	choices.clear()
	_fire_list(rec.get("events", []))
	line = context.substitute(str(rec.get("text", ""))) if context != null else str(rec.get("text", ""))
	line_shown.emit(line)


func _enter_choice(rec: Dictionary) -> void:
	_fire_list(rec.get("events", []))
	choices.clear()
	var raw: Variant = rec.get("options", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry: Variant in raw as Array:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var opt: Dictionary = entry as Dictionary
			if not DialogueCondition.matches(opt.get("if", opt.get("when")), context):
				continue
			var copy: Dictionary = opt.duplicate(true)
			copy["text"] = context.substitute(str(copy.get("text", ""))) if context != null else str(copy.get("text", ""))
			choices.append(copy)
	if choices.is_empty():
		var fallback := StringName(str(rec.get("next", "")))
		if fallback == &"":
			_finish()
			return
		_goto(fallback)
		return
	waiting_choice = true
	line = context.substitute(str(rec.get("prompt", ""))) if context != null else str(rec.get("prompt", ""))
	choices_shown.emit(choices)


func _pick_branch(rec: Dictionary) -> StringName:
	var raw: Variant = rec.get("when", rec.get("options", []))
	if typeof(raw) != TYPE_ARRAY:
		return &""
	for entry: Variant in raw as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var arm: Dictionary = entry as Dictionary
		if arm.has("if") and not DialogueCondition.matches(arm["if"], context):
			continue
		return StringName(str(arm.get("goto", "")))
	return &""


func _pick_random(rec: Dictionary) -> StringName:
	var raw: Variant = rec.get("options", [])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		return &""
	var pool: Array[Dictionary] = []
	var total := 0
	for entry: Variant in raw as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var opt: Dictionary = entry as Dictionary
		if not DialogueCondition.matches(opt.get("if", opt.get("when")), context):
			continue
		var w: int = maxi(int(opt.get("weight", 1)), 1)
		pool.append(opt)
		total += w
	if pool.is_empty() or context == null:
		return &""
	if context.rng == null:
		context.rng = RandomNumberGenerator.new()
		context.rng.randomize()
	var pick: int = context.rng.randi_range(0, total - 1)
	for opt: Dictionary in pool:
		pick -= maxi(int(opt.get("weight", 1)), 1)
		if pick < 0:
			return StringName(str(opt.get("goto", "")))
	return StringName(str(pool[0].get("goto", "")))


func _fire_list(raw: Variant) -> void:
	events_this_step.clear()
	if typeof(raw) != TYPE_ARRAY:
		return
	for entry: Variant in raw as Array:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = entry as Dictionary
		events_this_step.append(event)
		_apply_event(event)
		event_fired.emit(event)


func _apply_event(event: Dictionary) -> void:
	var op := String(event.get("op", event.get("type", "")))
	match op:
		"set_var":
			if context != null:
				context.set_var(str(event.get("name", "")), event.get("value", 0))
		"add_var":
			if context != null:
				var key := str(event.get("name", ""))
				context.set_var(key, int(context.get_var(key, 0)) + int(event.get("amount", 1)))
		"add_friendship":
			if _state != null:
				_state.add_friendship(int(event.get("amount", 1)))
			elif context != null:
				context.friendship = clampi(
					context.friendship + int(event.get("amount", 1)),
					VillagerState.FRIENDSHIP_MIN,
					VillagerState.FRIENDSHIP_MAX
				)
		"give_item":
			if context != null and context.inventory != null:
				var data: ItemData = ItemCatalog.get_item(StringName(str(event.get("item", ""))))
				if data != null:
					context.inventory.add(data, int(event.get("count", 1)))
		"take_item":
			if context != null and context.inventory != null:
				context.inventory.remove(
					StringName(str(event.get("item", ""))), int(event.get("count", 1))
				)
		"set_mood":
			if _state != null:
				_state.mood = _mood_from(str(event.get("mood", "normal")))
			elif context != null:
				context.mood = _mood_from(str(event.get("mood", "normal")))
		"notice":
			Game.post_notice(str(event.get("text", "")))


func _mood_from(name: String) -> VillagerState.Mood:
	match name.to_lower():
		"happy":
			return VillagerState.Mood.HAPPY
		"angry":
			return VillagerState.Mood.ANGRY
		"sad":
			return VillagerState.Mood.SAD
		"sleepy":
			return VillagerState.Mood.SLEEPY
		"pitfall":
			return VillagerState.Mood.PITFALL
		_:
			return VillagerState.Mood.NORMAL


func _current() -> Dictionary:
	if conversation == null:
		return {}
	return conversation.node(node_id)


func _finish() -> void:
	if done:
		return
	done = true
	waiting_choice = false
	finished.emit()


const KIND_LINE := DialogueData.KIND_LINE
