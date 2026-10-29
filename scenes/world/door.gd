extends Node3D

## Door / entrance sensor. Compose under a building or place as its own world object.
## Outdoor: enter the mapped interior. Indoor: leave or walk to a linked room.

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i.ONE
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = false
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var label: String = "Door"
@export var verb: StringName = &"enter"
@export var closed_notice: String = "The door is locked."
@export var linked_room_id: StringName = &""
@export var exits_interior: bool = false
## Walk into the sensor to enter (museum, police box, lighthouse). No A prompt while open.
@export var auto_enter: bool = false
## Optional decomp spawn when following `linked_room_id`.
@export var has_linked_spawn: bool = false
## Where the linked room puts the player (metres from its corner).
@export var linked_spawn: Vector3 = Vector3.ZERO
@export var linked_spawn_yaw: float = 0.0

## `aMsm_check_player`: the outdoor museum door fires with the player's centre within √1100 GX
## of its stand (`t < 1100`)...
const MUSEUM_STAND_RADIUS := 33.166 * FieldCatalog.GX_TO_METERS
## ...and facing the door to within 45° (`rotation.y` strictly between 0x6000 and 0xA000).
const MUSEUM_STAND_FACING := PI / 4.0


func _ready() -> void:
	add_to_group("interactable")


func should_auto_enter() -> bool:
	## Outdoor walk-ins (museum, police box, lighthouse), indoor wing links and the museum exit: no A prompt.
	if not auto_enter:
		return false
	## Just spawned on/near a door — wait until the player walks clear.
	if Game.block_auto_enter_doors:
		return false
	if Game.is_indoors():
		## Wing links + entrance Exit (`exits_interior`); not house door_cell warps.
		## `Player_actor_check_nextgoto`: the warp is the item on the player's own unit, so
		## the player's centre has to be on the door, not just reaching for it.
		return (linked_room_id != &"" or exits_interior) and _player_centre_on_sensor()
	var target: StringName = _enter_target()
	if target == &"":
		return false
	var room_id: StringName = InteriorCatalog.resolve_entry(target)
	if room_id == &"":
		return false
	var room: Room = Game.interiors.room(room_id)
	if room == null or not InteriorCatalog.is_open_now(room):
		return false
	return not _is_outdoor_museum() or _player_at_museum_stand()


func _player_centre_on_sensor() -> bool:
	var player := Player.find(get_tree())
	var shape_node := get_node_or_null("InteractVolume/CollisionShape3D") as CollisionShape3D
	if player == null or shape_node == null or not (shape_node.shape is BoxShape3D):
		return false
	var half: Vector3 = (shape_node.shape as BoxShape3D).size * 0.5
	var local: Vector3 = shape_node.global_transform.affine_inverse() * player.global_position
	return absf(local.x) <= half.x and absf(local.z) <= half.z


func _is_outdoor_museum() -> bool:
	var host: Node = get_parent()
	return host != null and "visual_id" in host and HostCollision.is_museum(host.get("visual_id") as StringName)


func _player_at_museum_stand() -> bool:
	var player := Player.find(get_tree())
	if player == null:
		return false
	var to := Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z)
	if to.length() >= MUSEUM_STAND_RADIUS:
		return false
	## Into the door is the building's -Z (it faces south at yaw 0, like `-DEG2SHORT_ANGLE(180)`).
	var into: Vector3 = -(get_parent() as Node3D).global_basis.z
	var into_yaw: float = atan2(into.x, into.z)
	return absf(angle_difference(player.facing_yaw(), into_yaw)) < MUSEUM_STAND_FACING


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	## Outdoor exit is a walk-on warp (`EXIT_DOOR`); no A prompt.
	if Game.is_indoors() and exits_interior:
		## Silent probe so auto-enter can fire; never show Leave.
		if should_auto_enter():
			return [Interaction.of(Interaction.ENTER, "", 20)]
		return []
	## Open auto-enter (outdoor museum or indoor wing link): silent verb so the probe
	## still finds us; player walks in without an E prompt.
	if should_auto_enter():
		return [Interaction.of(Interaction.ENTER, "", 20)]
	## Walk-on doors never prompt (`aMsm_check_player`, the museum `DOOR` / `EXIT_DOOR` units):
	## off the trigger, or closed, there is simply nothing to press.
	if auto_enter:
		return []
	if Game.is_indoors() and linked_room_id != &"":
		return [Interaction.of(Interaction.ENTER, "Enter %s" % label, 12)]
	var prompt: String = "Enter %s" % label if verb == Interaction.ENTER else String(verb).capitalize()
	if verb == Interaction.SHOP:
		prompt = "Shop"
		var shop_room: Room = _resolved_room()
		if shop_room != null and not InteriorCatalog.is_open_now(shop_room):
			prompt = "Shop (closed)"
	return [Interaction.of(verb, prompt, 12)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null:
		return false
	if Game.is_indoors() and exits_interior:
		## Museum Exit sensor: player stops, then the wipe warps the scene.
		if action.id != Interaction.ENTER:
			return false
		var exit_player := Player.find(get_tree())
		if exit_player != null and is_instance_valid(exit_player):
			exit_player.stop_for_door()
		await SceneTransition.play_wipe_out(SceneTransition.Style.IRIS)
		return Game.exit_interior()
	if Game.is_indoors() and linked_room_id != &"":
		if action.id != Interaction.ENTER:
			return false
		## Museum wing links (`Player_actor_set_nextgoto_info_type1`): the player brakes to a
		## stand (`INVADE`) under a plain fade — `MUSEUM_*_door_data` wipe type 2, drawn in the
		## black `setcolor(0)` — and the music runs on (`FADE_TYPE_OTHER_ROOM`).
		var museum_link: bool = _is_museum_room(linked_room_id)
		if museum_link:
			var link_player := Player.find(get_tree())
			if link_player != null and is_instance_valid(link_player):
				link_player.stop_for_door()
		else:
			await _play_indoor_link_enter()
		await SceneTransition.play_wipe_out(
			SceneTransition.Style.FADE if museum_link else SceneTransition.Style.IRIS
		)
		var entered: bool = false
		if has_linked_spawn:
			entered = Game.try_enter_interior(linked_room_id, linked_spawn, linked_spawn_yaw)
		else:
			entered = Game.try_enter_interior(linked_room_id)
		return entered
	if action.id != verb:
		return false
	if verb == Interaction.SHOP:
		var shop_target: StringName = _enter_target()
		var shop_room: Room = _resolved_room(shop_target)
		if shop_room != null and not InteriorCatalog.is_open_now(shop_room):
			Game.post_notice(InteriorCatalog.closed_notice(shop_room))
			return false
		if shop_target != &"":
			await StructureDoor.play_enter(self)
			await SceneTransition.play_wipe_out(SceneTransition.Style.IRIS)
			if Game.try_enter_interior(shop_target):
				return true
			SceneTransition.cancel_wipe()
			_end_player_door_enter()
			if InteriorCatalog.resolve_entry(shop_target) != &"":
				return false
		Game.post_notice("The shop is open.")
		return true
	var target: StringName = _enter_target()
	if target != &"":
		if InteriorCatalog.resolve_entry(target) == &"":
			Game.post_notice(closed_notice)
			return true
		## Outdoor museum still plays INTO_S1 (`aMsm` door_type1) before the wipe.
		await StructureDoor.play_enter(self)
		await SceneTransition.play_wipe_out(SceneTransition.Style.IRIS)
		if Game.try_enter_interior(target):
			return true
		SceneTransition.cancel_wipe()
		_end_player_door_enter()
		if InteriorCatalog.resolve_entry(target) != &"":
			return false
	Game.post_notice(closed_notice)
	return true


func _resolved_room(target: StringName = &"") -> Room:
	var entry: StringName = target if target != &"" else _enter_target()
	if entry == &"":
		return null
	var room_id: StringName = InteriorCatalog.resolve_entry(entry)
	if room_id == &"" or Game.interiors == null:
		return null
	return Game.interiors.room(room_id)


func _is_museum_room(room_id: StringName) -> bool:
	if room_id == &"" or Game.interiors == null:
		return false
	var room: Room = Game.interiors.room(room_id)
	return room != null and room.kind == Room.Kind.MUSEUM


func _play_indoor_link_enter() -> void:
	## Wing doors have no structure cKF — walk INTO_S1 into the sensor like outdoor museum.
	var player := Player.find(get_tree())
	if player == null or not is_instance_valid(player):
		return
	var target := Vector3(global_position.x, player.global_position.y, global_position.z)
	var to: Vector3 = target - player.global_position
	to.y = 0.0
	var yaw: float = atan2(to.x, to.z) if to.length_squared() > 0.0001 else 0.0
	player.doors.begin_door_enter(target, yaw, true)
	await player.doors.await_door_enter()
	player.doors.end_door_enter()


func _enter_target() -> StringName:
	if occupant_id != &"":
		return occupant_id
	var parent: Node = get_parent()
	if parent != null and "occupant_id" in parent:
		var from_parent: StringName = parent.get("occupant_id") as StringName
		if from_parent != &"":
			return from_parent
	return &""


func _end_player_door_enter() -> void:
	## Clear scripted `keep_h` walk-in when the indoor load fails (scene stayed outdoors).
	StructureDoor.end_enter(self)
