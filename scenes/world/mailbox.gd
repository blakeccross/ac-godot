extends StaticBody3D

## The player's house mailbox (`ac_mailbox` / `ACTOR_PROP_MAILBOX0`). Delivered letters
## land in `Inventory._mail` with a `RECV*` font; this is where the player reads them.

## `obj_s_post` / `obj_w_post` (`ac_mailbox`): box + post + raiseable flag, seasonal pair.
## `world_builder.gd::_apply_common` overwrites this with the placement id at spawn
## (`player_mailbox`, or `player_mailbox_1/2/3` for the three unclaimed house plots —
## `ACTOR_PROP_MAILBOX1`–`3` have no save data behind them, decomp: "only player 0's
## private data is filled"). Only the real player's box reads/reacts to `Inventory`.
@export var occupant_id: StringName = &"player"
@export var footprint: Vector2i = Vector2i(1, 1)
## Compass direction the mail slot / flag face (where the player stands to read it).
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.NORTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &"obj_s_post"

## `obj_s_post` rest pose points the slot at −X; offset so `grid_facing` reads as "slot dir".
const SLOT_REST_OFFSET := -PI * 0.5

## Baked cKF clips on `obj_s_post` / `obj_w_post`: flag-down idle, raise, waving-up loop,
## lower, and the lid-open beat played when the box is checked.
const ANIM_FLAG_DOWN := "obj_s_post"
const ANIM_FLAG_RAISE := "obj_s_post_flag_on1"
const ANIM_FLAG_UP_WAIT := "obj_s_post_flag_on_wait1"
const ANIM_FLAG_LOWER := "obj_s_post_flag_off1"
const ANIM_OPEN := "obj_s_post_open1"

var _has_mesh: bool = false
var _anim: AnimationPlayer
var _flag_up: bool = false
var _pending_transition: Callable
var _checking: bool = false


func _ready() -> void:
	add_to_group("interactable")
	apply_grid_yaw(grid_facing)
	if visual_id != &"" and not FieldCatalog.mesh_paths(visual_id).is_empty():
		GeneratedVisual.attach(self, visual_id)
		_has_mesh = true
		var placeholder: Node = get_node_or_null("Post")
		if placeholder != null:
			placeholder.queue_free()
		var box_mesh: Node = get_node_or_null("Box")
		if box_mesh != null:
			box_mesh.queue_free()
		_anim = GeneratedVisual.find_animation_player(self)
	HostCollision.apply_box(self, footprint, HostCollision.CELL, 1.0)
	if is_owned() and Game != null and Game.inventory != null:
		if not Game.inventory.mail_changed.is_connected(_on_mail_changed):
			Game.inventory.mail_changed.connect(_on_mail_changed)
	_sync_flag(true)


## Unclaimed house plots (`player_mailbox_1`–`3`) have no player behind them — decoration
## only, flag always down, no "check mailbox" prompt.
func is_owned() -> bool:
	return occupant_id == &"player" or occupant_id == &"player_mailbox"


func _exit_tree() -> void:
	if Game != null and Game.inventory != null and Game.inventory.mail_changed.is_connected(_on_mail_changed):
		Game.inventory.mail_changed.disconnect(_on_mail_changed)


func apply_grid_yaw(facing: WorldGrid.Facing) -> void:
	grid_facing = facing
	rotation.y = WorldGrid.yaw_for_facing(facing) + SLOT_REST_OFFSET


func refresh_seasonal_visual() -> void:
	if _has_mesh:
		GeneratedVisual.refresh(self, visual_id)
		_anim = GeneratedVisual.find_animation_player(self)
		_sync_flag(true)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if not is_owned():
		return []
	var label := "Check mailbox"
	if Game != null and Game.inventory != null and Game.inventory.unread_mail_count() > 0:
		label = "Read mail (%d)" % Game.inventory.unread_mail_count()
	return [Interaction.of(Interaction.READ, label, 10)]


## `aMBX_pl_open` / `aMBX_pl_close`: the lid finishes opening (its own multi-frame beat)
## before the Letters menu appears, and plays the same clip in reverse once that menu
## closes — the box is never mid-open while the player is browsing mail.
func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if not is_owned() or action == null or action.id != Interaction.READ or Game == null or _checking:
		return false
	_checking = true
	var inv: Inventory = Game.inventory
	await _play_clip(ANIM_OPEN)
	if not is_instance_valid(self):
		return true
	if inv == null or inv.received_mail_count() <= 0:
		Game.post_notice("The mailbox is empty.")
	else:
		var ui: Node = get_tree().get_first_node_in_group("inventory_ui") if get_tree() != null else null
		if ui != null and ui.has_method("open_letters"):
			ui.call("open_letters")
			if ui.has_signal("closed"):
				await ui.closed
		else:
			Game.post_notice("You have %d letter(s). Check your Letters page." % inv.received_mail_count())
	if not is_instance_valid(self):
		return true
	await _play_clip(ANIM_OPEN, true)
	if is_instance_valid(self):
		_sync_flag(true)
		_checking = false
	return true


## Delivered/read mail raises or lowers the flag (`ACTOR_PROP_MAILBOX0` flag SE), even
## while nobody is standing at the box — the delivery-day "you've got mail" tell.
func _on_mail_changed() -> void:
	_sync_flag(false)


func _sync_flag(instant: bool) -> void:
	var want_up: bool = (
		is_owned() and Game != null and Game.inventory != null and Game.inventory.unread_mail_count() > 0
	)
	if instant:
		_flag_up = want_up
		var pose: String = ANIM_FLAG_UP_WAIT if want_up else ANIM_FLAG_DOWN
		if _has_clip(pose):
			_anim.play(pose)
		return
	if want_up == _flag_up:
		return
	_flag_up = want_up
	if want_up:
		_queue_after(ANIM_FLAG_RAISE, ANIM_FLAG_UP_WAIT)
	else:
		_queue_after(ANIM_FLAG_LOWER, ANIM_FLAG_DOWN)


## Plays `clip` (or in reverse) and waits for it to actually finish, tolerating another
## clip (e.g. a flag raise triggered by mail arriving mid-open) interrupting it.
func _play_clip(clip: String, backwards: bool = false) -> void:
	if _anim == null or not _has_clip(clip):
		return
	if backwards:
		_anim.play_backwards(clip)
	else:
		_anim.play(clip)
	while (
		is_instance_valid(_anim)
		and _anim.is_playing()
		and _anim.current_animation == clip
	):
		await _anim.animation_finished


## Plays `clip`, then chains into `next_clip` once it finishes (replacing any pending chain).
func _queue_after(clip: String, next_clip: String) -> void:
	if _anim == null:
		return
	if _pending_transition.is_valid() and _anim.animation_finished.is_connected(_pending_transition):
		_anim.animation_finished.disconnect(_pending_transition)
	if not _has_clip(clip):
		if _has_clip(next_clip):
			_anim.play(next_clip)
		return
	_anim.play(clip)
	_pending_transition = _on_clip_finished.bind(next_clip)
	_anim.animation_finished.connect(_pending_transition, CONNECT_ONE_SHOT)


func _on_clip_finished(_name: StringName, next_clip: String) -> void:
	if _has_clip(next_clip):
		_anim.play(next_clip)


func _has_clip(clip: String) -> bool:
	return _anim != null and _anim.has_animation(clip)
