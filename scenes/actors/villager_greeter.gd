class_name VillagerGreeter
extends Node

## Two villagers meeting on the road: pairing up those free to greet, walking to face each
## other, the bow and the exchange (`VillagerGreeting`, `aNPC_check_greeting`), then going
## their ways. A child of the `Villager`; it reads the villager's motor and AI directly.

var _greet: Villager.Greet = Villager.Greet.TURN
## `condition_info.greeting_flag`: 1 rolled the reaction, 2 didn't, 3 / 4 / 5 changes
## clothes / umbrella / both.
var _greet_flag: int = 0
var _greet_timer: float = 0.0
static var _pair_frame: int = -1

## The Villager this belongs to (the parent), found on first use: tests build scenes
## without adding them to the tree.
var _villager: Villager:
	get:
		if _villager == null:
			_villager = get_parent() as Villager
		return _villager


## May this villager be paired up (`aNPC_check_cond_to_greeting`)? Only the ones wandering
## outdoors get the think interrupt that starts the greeting.
func free_to_greet() -> bool:
	return (
		not _villager.indoor_resident and _villager.ai.is_present() and _villager.ai.is_wandering() and not _villager.ai.is_talking()
		and _villager._pal == null and _villager._pal_ignore <= 0.0 and _villager._act == Villager.Act.NONE and _villager._react == Villager.React.NONE
		and VillagerGreeting.can_greet(_villager.state)
	)


## `aNPC_greeting_area_check`, once a physics frame for everyone.
func pair_greetings() -> void:
	var frame: int = Engine.get_physics_frames()
	if _pair_frame == frame or get_tree() == null:
		return
	_pair_frame = frame
	var free: Array = []
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		if node is Villager and (node as Villager).greeter.free_to_greet():
			free.append(node)
	for pair: Array in VillagerGreeting.pair_up(free):
		(pair[0] as Villager)._pal = pair[1]
		(pair[1] as Villager)._pal = pair[0]


func _greet_info(v: Node) -> Dictionary:
	var vd: VillagerData = v.get("data")
	var slot: int = Game.residents.slot_of(vd.id) if vd != null and Game != null and Game.residents != null else -1
	return {"state": v.get("state"), "data": vd, "slot": slot}


## `aNPC_act_greeting_init_proc` / `aNPC_act_greeting_reaction`.
func begin_greeting() -> bool:
	var pal: Node3D = _villager._pal
	if pal == null or not is_instance_valid(pal) or (pal as Villager)._pal != _villager:
		_villager._pal = null
		return false
	if _villager.ai.is_talking() or (pal.get("ai") as VillagerAI).is_talking():
		## `mDemo_IS_ACTOR_TALKING`: someone is talking to the player — call it off.
		_villager._pal = null
		(pal as Villager)._pal = null
		return false
	var flag: int = 2
	var pal_flag: int = int((pal as Villager).greeter._greet_flag)
	if pal_flag not in [1, 3, 4, 5]:
		var rng := _villager._outdoor_rng
		VillagerGreeting.react(_greet_info(_villager), _greet_info(pal), _around_npcs(pal), Game.residents, rng)
		flag = 1
	if _villager.state != null:
		if _villager._cloth_key() != _villager._drawn_cloth:
			flag = 3
		if _villager.state.umbrella_design != _villager._drawn_umb:
			flag = 5 if flag == 3 else 4
	_greet_flag = flag
	_villager._act = Villager.Act.GREET
	_greet = Villager.Greet.TURN
	_villager._motor.arrive()
	_villager._play_clip(Villager.ANIM_WAIT, true)
	return true


## `aNPC_make_aroundNpcInfoList`: residents one acre away (not these two) that have met the
## player, friendliest first.
func _around_npcs(pal: Node3D) -> Array:
	var out: Array = []
	if Game == null or Game.residents == null:
		return out
	var here: Vector2i = _villager._current_block()
	var nodes: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group("villagers"):
		var vd: VillagerData = node.get("data")
		if vd != null:
			nodes[vd.id] = node
	for id: StringName in Game.residents.resident_ids():
		if (_villager.data != null and id == _villager.data.id) or (pal.get("data") != null and id == (pal.get("data") as VillagerData).id):
			continue
		var node: Node3D = nodes.get(id) as Node3D
		var block: Vector2i
		if node != null:
			block = VillagerWalk.block_from_cell(_grid_cell(node.global_position))
		else:
			block = VillagerWalk.block_from_cell(Game.residents.home_of(Game.residents.slot_of(id)))
		if absi(block.x - here.x) + absi(block.y - here.y) != 1:
			continue
		var st: VillagerState = Game.villagers.get_or_create(id)
		if st.relationship == null or not st.relationship.has_memory:
			continue
		out.append({
			"state": st, "data": VillagerCatalog.get_villager(id), "friendship": st.friendship,
			"loaded": node != null and (node.get("ai") as VillagerAI).is_present(),
		})
	VillagerGreeting.sort_around(out)
	return out


func _grid_cell(pos: Vector3) -> Vector2i:
	var bg: Array = _villager._bg()
	if bg.size() == 2:
		return (bg[1] as WorldGrid).world_to_cell(pos)
	return Vector2i.ZERO


func tick_greeting(delta: float) -> void:
	var pal: Node3D = _villager._pal
	if pal == null or not is_instance_valid(pal) or (pal as Villager)._pal != _villager:
		_villager._pal = null
		_end_greeting()
		return
	var to: Vector3 = pal.global_position - _villager.global_position
	to.y = 0.0
	var clip_done: bool = (
		_villager._body_anim == null or not _villager._body_anim.is_playing() or _villager._body_anim.current_animation != _villager._clip
	)
	match _greet:
		Villager.Greet.TURN:
			_villager._motor.turn_toward(delta, _villager.global_position, pal.global_position)
			if absf(angle_difference(_villager._motor.facing, atan2(to.x, to.z))) < deg_to_rad(10.0):
				if to.length() < VillagerGreeting.APPROACH_NEAR:
					_greet = Villager.Greet.WAIT
				else:
					_greet = Villager.Greet.APPROACH
					_greet_timer = VillagerGreeting.APPROACH_SECONDS
					_villager._play_clip(Villager.ANIM_WALK, true)
		Villager.Greet.APPROACH:
			## `aNPC_act_greeting_approach`: walk over for at most 80 frames.
			_greet_timer -= delta
			_villager._motor.turn_toward(delta, _villager.global_position, pal.global_position)
			var step: Vector3 = Vector3(sin(_villager._motor.facing), 0.0, cos(_villager._motor.facing)) * _villager._motor.walk_speed
			_villager.velocity.x = step.x
			_villager.velocity.z = step.z
			_villager.move_and_slide()
			_villager.velocity.x = 0.0
			_villager.velocity.z = 0.0
			if to.length() < VillagerGreeting.APPROACH_NEAR or _greet_timer <= 0.0 or _villager.get_slide_collision_count() > 0:
				_greet = Villager.Greet.WAIT
				_villager._play_clip(Villager.ANIM_WAIT, true)
		Villager.Greet.WAIT:
			## `aNPC_act_greeting_wait`: bow together once both are waiting.
			if int((pal as Villager).greeter._greet) == Villager.Greet.WAIT and int((pal as Villager)._act) == Villager.Act.GREET:
				(pal as Villager).greeter._start_bow()
				_start_bow()
		Villager.Greet.BOW:
			if clip_done:
				if _greet_flag >= 3:
					## `NA_SE_WEAR`, then `GET_CHANGE1`.
					_greet = Villager.Greet.CHANGE
					_villager._play_clip(VillagerGreeting.CHANGE_CLIP, false)
				else:
					_greeting_end()
		Villager.Greet.CHANGE:
			if clip_done:
				_villager._drawn_cloth = _villager._cloth_key()
				_villager._drawn_umb = _villager.state.umbrella_design if _villager.state != null else -1
				_villager._apply_design_wear()
				_greet_flag = 0
				_greeting_end()
		Villager.Greet.HOLD:
			pass
	if _villager._model != null:
		_villager._model.rotation.y = _villager._motor.facing


func _start_bow() -> void:
	_greet = Villager.Greet.BOW
	var looks: int = clampi(int(_villager._looks()), 0, VillagerGreeting.GREETING_CLIPS.size() - 1)
	_villager._play_clip(VillagerGreeting.GREETING_CLIPS[looks], false)


## `aNPC_setup_greeting_end`: wait while the partner is still changing, else both finish.
func _greeting_end() -> void:
	var pal: Node3D = _villager._pal
	if pal != null and is_instance_valid(pal) and int((pal as Villager).greeter._greet_flag) >= 3 and int((pal as Villager)._act) == Villager.Act.GREET:
		_greet = Villager.Greet.HOLD
		_villager._play_clip(Villager.ANIM_WAIT, true)
		return
	if pal != null and is_instance_valid(pal) and (pal as Villager)._pal == _villager:
		(pal as Villager).greeter._end_greeting()
	_end_greeting()


## `aNPC_setup_greeting_end_sub`.
func _end_greeting() -> void:
	_villager._pal = null
	_villager._pal_ignore = VillagerGreeting.IGNORE_SECONDS
	_greet_flag = 0
	if _villager._act == Villager.Act.GREET:
		_villager._act = Villager.Act.NONE
		_villager._play_clip(Villager.ANIM_WAIT, true)
