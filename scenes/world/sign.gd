extends StaticBody3D

## Readable field sign. During first-job notice chore, Read becomes a write confirm.

@export var message: String = "Welcome to the acre."
@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.FURNITURE
@export var visual_id: StringName = &"SIGNBOARD"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_box(self, footprint, HostCollision.CELL, 1.4)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


func get_interactions(_ctx: InteractionContext) -> Array[Interaction]:
	if _needs_first_job_notice():
		return [Interaction.of(Interaction.READ, "Post a notice", 8)]
	return [Interaction.of(Interaction.READ, "Read sign", 6)]


func interact(action: Interaction, _ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.READ:
		return false
	if _needs_first_job_notice():
		return _post_first_job_notice()
	Game.post_notice(message)
	return true


func _needs_first_job_notice() -> bool:
	if Game == null or Game.first_job == null:
		return false
	var job: FirstJob = Game.first_job
	return (
		job.kind == FirstJob.Kind.POST_NOTICE
		and job.progress == FirstJob.PROGRESS_ACTIVE
	)


func _post_first_job_notice() -> bool:
	## `mNT_finish_notice_first_job` on confirmed write.
	var body: String = "Hello, town! — %s" % (
		Game.player_name if Game != null and Game.player_name != "" else "a new neighbor"
	)
	message = body
	Game.first_job.mark_notice_posted()
	Game.post_notice("Posted: %s" % body)
	Game.set_interact_prompt("Talk to Tom Nook")
	return true
