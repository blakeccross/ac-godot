extends StaticBody3D

## Outdoor rock FG item (`ROCK_A`–`ROCK_E`). The shovel bounces off it (`reflect_scoop`,
## `ply_1_not_dig1`, contact on frame 13); the day's money rock pays out Bells (`MoneyRock`).

const PICKUP_SCENE := preload("res://scenes/world/item_pickup.tscn")
const HIT_FRAME := 13.0

@export var occupant_id: StringName = &""
@export var footprint: Vector2i = Vector2i(1, 1)
@export var grid_facing: WorldGrid.Facing = WorldGrid.Facing.SOUTH
@export var occupy_grid: bool = true
@export var place_kind: WorldGrid.PlaceKind = WorldGrid.PlaceKind.PLANT
@export var visual_id: StringName = &"ROCK_A"


func _ready() -> void:
	add_to_group("interactable")
	GeneratedVisual.attach(self, visual_id)
	HostCollision.apply_rock(self, footprint, HostCollision.CELL)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, visual_id)


func get_interactions(ctx: InteractionContext) -> Array[Interaction]:
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return []
	return [Interaction.of(Interaction.DIG, "Hit rock", 8, &"ply_1_not_dig1", HIT_FRAME)]


func is_rock() -> bool:
	return true


func interact(action: Interaction, ctx: InteractionContext) -> bool:
	if action == null or action.id != Interaction.DIG:
		return false
	if not ToolUse.has(ctx, ToolData.Kind.SHOVEL):
		return false
	PlayerSe.scoop_rock(self)
	if MoneyRock.is_money_rock(occupant_id):
		_pay_out(ctx)
	return true


## `bIT_actor_ten_coin_entryR`: a bag pops out onto a free unit beside the rock.
func _pay_out(ctx: InteractionContext) -> void:
	var was_open: bool = MoneyRock.window_open()
	var bag: ItemData = MoneyRock.hit(occupant_id)
	if bag == null:
		return
	if not was_open:
		_arm_window_end()
	var world: Node = ctx.world if ctx != null else null
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	var objects: Node = world.get_node_or_null("Objects") if world != null else null
	if grid == null or objects == null:
		return
	var cell: Vector2i = MoneyRock.drop_cell(grid, grid.world_to_cell(global_position))
	if cell.x < 0:
		return
	var drop_id := StringName("%s_coin_%d_%d" % [String(occupant_id), MoneyRock.active_hits(), Time.get_ticks_msec()])
	var pickup: Node3D = PICKUP_SCENE.instantiate() as Node3D
	pickup.set("item", bag)
	pickup.set("persist_id", drop_id)
	pickup.set("occupant_id", drop_id)
	objects.add_child(pickup)
	var land: Vector3 = grid.cell_to_world(cell)
	if "layout" in world and world.layout != null:
		land.y = FieldCollision.ground_y(world.layout, cell, FieldCollision.FG_GROUND_DIST)
	var top: Vector3 = global_position + Vector3(0.0, 0.7, 0.0)
	pickup.call("begin_fall", top, land, 0.4, false)
	grid.place(drop_id, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.ITEM)
	Audio.play_se(MoneyRock.SE_HIT, self)


## `ten_coin_move`: once `left_frames` runs out the rock is plain again.
func _arm_window_end() -> void:
	var id: StringName = occupant_id
	var wait: float = DecompTime.ticks_to_sec(
		MoneyRock.window_frames(MoneyRock.money_power(), Game.destiny() == Game.Destiny.MONEY_LUCK)
	)
	get_tree().create_timer(wait).timeout.connect(
		func() -> void:
			if MoneyRock.is_money_rock(id) and not MoneyRock.window_open():
				MoneyRock.finish()
	)
