class_name ToolUse
extends RefCounted

## Equipped-tool lookup and empty-tile field verbs. Not an autoload.
## Hosts ask `has(ctx, kind)`; the player never switches on Shovel vs Axe.

## `mPlayer_ANIM_KOKERU*` — fall / get-up, by held item (`Get_PlayerAnimeIndex_fromItemKind_Tumble`).
const ANIM_KOKERU := "ply_1_kokeru1"
const ANIM_KOKERU_A := "ply_1_kokeru_a1"
const ANIM_KOKERU_N := "ply_1_kokeru_n1"
const ANIM_KOKERU_GETUP := "ply_1_kokeru_getup1"
const ANIM_KOKERU_GETUP_A := "ply_1_kokeru_getup_a1"
const ANIM_KOKERU_GETUP_N := "ply_1_kokeru_getup_n1"
## `mPlayer_ANIM_NOT_DIG1`: the shovel bounces off, contact on frame 13.
const ANIM_NOT_DIG := &"ply_1_not_dig1"
const NOT_DIG_FRAME := 13.0

## `mPlib_Get_scoop_request_index` on a free unit: dig, swing at air (`AIR_SCOOP`, water) or
## bounce off (`REFLECT_SCOOP`) with the clang for what it hit.
enum Scoop { DIG, AIR, HIT_STONE, HIT_WOOD, HIT_BUSH }
## `mPlayer_ANIM_AXE_HANE1`: the axe bounces off a rock or a bank, contact on frame 15.
const ANIM_AXE_HANE := &"ply_1_axe_hane1"
## `SetAngleSpeedF_Reflect_*`: the knock-back speed (GX per frame).
const REFLECT_STEP_BACK := 4.8
const AXE_HIT_FRAME := 15.0
## `Player_actor_Check_axe_after`: a unit 31 GX or more above the feet is a bank.
const AXE_BANK_GX := 31.0
## `mCoBG_ATTRIBUTE_BUSH` / `_WOOD` (`mCoBG_WoodSoundEffect` also takes the wood bridge).
const ATTR_BUSH := 9
const ATTR_WOOD := 23
## `mFI_GetDigStatus`: a golden shovel finds 100 Bells one dig in ten, away from the last.
const GOLD_BELLS_CHANCE := 10


static func equipped(ctx: InteractionContext) -> ToolData:
	if ctx == null or ctx.inventory == null:
		return null
	var data: ItemData = ItemCatalog.get_item(ctx.inventory.equipment_id)
	return data as ToolData


static func kind(ctx: InteractionContext) -> ToolData.Kind:
	var tool: ToolData = equipped(ctx)
	if tool == null:
		return ToolData.Kind.NONE
	return tool.kind


static func has(ctx: InteractionContext, want: ToolData.Kind) -> bool:
	return kind(ctx) == want


static func field_action(ctx: InteractionContext) -> Interaction:
	var tool: ToolData = equipped(ctx)
	if tool == null or tool.field_verb == &"":
		return null
	## A line already out replaces the cast verb, and survives the player turning away.
	if tool.field_verb == Interaction.CAST and Fishing.is_active():
		return Fishing.field_action()
	if not _field_ok(tool, ctx):
		return null
	var prompt: String = tool.field_prompt
	if prompt.is_empty():
		prompt = tool.display_name
	var effect_frame: float = -1.0
	if tool.field_verb == Interaction.CAST:
		effect_frame = Fishing.CAST_RELEASE_FRAME
	elif tool.field_verb == Interaction.DIG:
		## Scoop dig SE / hole write at frame 15 (`Player_actor_SetSound_Dig_scoop`).
		effect_frame = 15.0
		if ball_ahead(ctx) != null:
			return Interaction.of(tool.field_verb, prompt, tool.field_priority, ANIM_NOT_DIG, NOT_DIG_FRAME)
		if tool.field_require == ToolData.FieldRequire.EMPTY_GROUND:
			var outcome: Scoop = scoop_outcome(ctx)
			if outcome >= Scoop.HIT_STONE:
				return Interaction.of(tool.field_verb, prompt, tool.field_priority, ANIM_NOT_DIG, NOT_DIG_FRAME)
			if outcome == Scoop.AIR:
				## `AIR_SCOOP`: nothing to hit, the swing just finishes.
				effect_frame = -1.0
	elif tool.field_verb == Interaction.AIR_AXE and (axe_hits_bank(ctx) or ball_ahead(ctx) != null):
		return Interaction.of(tool.field_verb, prompt, tool.field_priority, ANIM_AXE_HANE, AXE_HIT_FRAME)
	return Interaction.of(
		tool.field_verb, prompt, tool.field_priority, tool.field_anim, effect_frame
	)


## Prefer a higher-priority field verb (net swing, rod cast) over a weaker host.
static func resolve(hit: InteractionQuery, ctx: InteractionContext) -> InteractionQuery:
	var field: Interaction = field_action(ctx)
	if field == null:
		return hit
	if hit == null or hit.action == null or field.priority > hit.action.priority:
		var query := InteractionQuery.new()
		query.host = null
		query.action = field
		return query
	return hit


static func apply_field(action: Interaction, ctx: InteractionContext) -> bool:
	var tool: ToolData = equipped(ctx)
	if tool == null or action == null:
		return false
	if tool.field_verb == Interaction.CAST:
		return _apply_rod(tool, action, ctx)
	## The net's A raises it; `NetSwing`, driven by the player tick by tick, owns the rest.
	if tool.field_verb == Interaction.SWING_NET:
		return action.id == tool.field_verb
	if action.id != tool.field_verb:
		return false
	if not _field_ok(tool, ctx):
		return false
	## `ROTATE_UMBRELLA`: the twirl is the whole verb (clip + SE on the player), and in rain
	## it flings water off the canopy (`ef_kasamizu`).
	if tool.kind == ToolData.Kind.UMBRELLA:
		var twirler := ctx.actor as Node3D
		if twirler != null:
			StepFx.umbrella_spray(twirler.global_position, facing_yaw(ctx))
		return true
	## `REFLECT_SCOOP` / `REFLECT_AXE` on the ball (`aBALL_STATE_PLAYER_HIT_*`).
	var ball: FieldBall = ball_ahead(ctx)
	if ball != null and (tool.field_verb == Interaction.DIG or tool.field_verb == Interaction.AIR_AXE):
		var who := ctx.actor as Node3D
		var yaw: float = facing_yaw(ctx)
		if tool.field_verb == Interaction.DIG:
			ball.hit_by_shovel(who.global_position, yaw)
			_reflect_scoop_fx(ctx)
		else:
			ball.hit_by_axe(who.global_position, yaw)
		return true
	if tool.field_verb == Interaction.AIR_AXE and axe_hits_bank(ctx):
		## `REFLECT_AXE` with no actor: `AXE_HIT` and the hard rumble.
		PlayerSe.axe_hit(ctx.actor if ctx != null else null)
		if ctx != null and ctx.actor != null and ctx.actor.has_method("recoil"):
			ctx.actor.call("recoil", REFLECT_STEP_BACK)
		wear_axe(ctx, true)
		_scare_fish(ctx)
		_stress_bugs(ctx)
		return true
	if tool.field_require == ToolData.FieldRequire.EMPTY_GROUND:
		var actor: Node = ctx.actor if ctx != null else null
		var outcome: Scoop = scoop_outcome(ctx)
		if outcome >= Scoop.HIT_STONE:
			PlayerSe.scoop_reflect(actor, outcome)
			_reflect_scoop_fx(ctx)
			_scare_fish(ctx)
			_stress_bugs(ctx)
			return true
		var cell: Vector2i = facing_cell(ctx)
		if outcome == Scoop.AIR or not HoleUse.dig(ctx, cell):
			PlayerSe.karaburi(actor)
			return false
		if tool.id == &"golden_shovel":
			_golden_bells(ctx, cell)
	if tool.field_notice != "":
		Game.post_notice(tool.field_notice)
	_scare_fish(ctx)
	_stress_bugs(ctx)
	return true


## `mPlib_Check_HitAxe` / `_StopNet` / `_HitScoop`: a swung tool sends nearby fish off. The
## rod returns early above, so casting never scares the fish you are casting at.
static func _scare_fish(ctx: InteractionContext) -> void:
	var school: FishSchool = Fishing.school_of(ctx)
	if school != null:
		school.notify_tool_swing()


static func _stress_bugs(ctx: InteractionContext) -> void:
	var field: BugField = Netting.field_of(ctx)
	if field != null:
		field.notify_tool_swing()


static func _apply_rod(tool: ToolData, action: Interaction, ctx: InteractionContext) -> bool:
	if Fishing.is_active():
		if action.id != Interaction.HOOK:
			return false
		Fishing.hook(ctx, Fishing.school_of(ctx))
		return true
	if action.id != tool.field_verb or not _field_ok(tool, ctx):
		return false
	if not Fishing.cast(ctx, cast_point(ctx)):
		return false
	if tool.field_notice != "":
		Game.post_notice(tool.field_notice)
	return true


static func facing_cell(ctx: InteractionContext) -> Vector2i:
	var grid: WorldGrid = _grid(ctx)
	if grid == null or ctx == null or ctx.actor == null:
		return Vector2i(-1, -1)
	return grid.world_to_cell(_facing_point(ctx, grid.cell_size))


## `m_player_main_ready_rod`: the landing spot is a fixed `Fishing.CAST_METERS` along the
## player's facing. Not the cell in front of them — the rod outreaches a cell by a long way.
static func cast_point(ctx: InteractionContext) -> Vector3:
	if ctx == null or ctx.actor == null:
		return Vector3.ZERO
	return _facing_point(ctx, Fishing.CAST_METERS)


static func _field_ok(tool: ToolData, ctx: InteractionContext) -> bool:
	match tool.field_require:
		ToolData.FieldRequire.WATER:
			return _cast_water_ok(ctx)
		ToolData.FieldRequire.EMPTY_GROUND:
			return _facing_empty_ground(ctx)
		_:
			return true


## `Player_actor_request_proc_index_fromReady_rod` probes the landing spot plus four corners
## at ±10 GX and needs every one to be water, so you cannot drop the bobber onto a spit of
## land or straddle the far bank. `FieldRequire.WATER` is the rod's alone; a tool that wants
## water in the cell it is standing next to should ask for its own requirement.
static func _cast_water_ok(ctx: InteractionContext) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if grid == null or ctx == null or ctx.actor == null:
		return false
	var centre: Vector3 = cast_point(ctx)
	var d: float = Fishing.CAST_PROBE_METERS
	var probes: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(-d, 0.0, d),
		Vector3(d, 0.0, d),
		Vector3(-d, 0.0, -d),
		Vector3(d, 0.0, -d),
	]
	for offset: Vector3 in probes:
		if grid.terrain_at(grid.world_to_cell(centre + offset)) != WorldGrid.Terrain.WATER:
			return false
	return true


## Any free unit in front: what the shovel does there is `scoop_outcome`'s call.
static func _facing_empty_ground(ctx: InteractionContext) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if grid == null:
		return false
	var cell: Vector2i = facing_cell(ctx)
	return grid.is_in_bounds(cell) and not grid.is_occupied(cell)


## `Player_actor_SetEffectHit_Reflect_scoop` at frame 13: the player steps back (4.8) and two
## impact stars fly from 37 GX ahead, 11 GX up (`eDig_Scoop_init` with `arg1` 1).
static func _reflect_scoop_fx(ctx: InteractionContext) -> void:
	var who := ctx.actor as Node3D if ctx != null else null
	if who == null or not who.is_inside_tree():
		return
	if who.has_method("recoil"):
		who.call("recoil", REFLECT_STEP_BACK)
	var yaw: float = facing_yaw(ctx)
	var gx: float = FieldCatalog.GX_TO_METERS
	var hit: Vector3 = who.global_position + Vector3(37.0 * sin(yaw) + 2.0 * cos(yaw), 0.0, 37.0 * cos(yaw) - 2.0 * sin(yaw)) * gx
	## `eDig_Scoop_init`: halfway between the strike and 30 GX ahead of the player.
	var ahead: Vector3 = who.global_position + Vector3(sin(yaw), 0.0, cos(yaw)) * 30.0 * gx
	var at := Vector3((hit.x + ahead.x) * 0.5, who.global_position.y + 11.0 * gx, (hit.z + ahead.z) * 0.5)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var host: Node = who.get_parent()
	for i: int in 2:
		ImpactStar.spawn(host, at, yaw + deg_to_rad(22.5), i, rng)


## The ball within the tool's reach in front of the player, or null.
static func ball_ahead(ctx: InteractionContext) -> FieldBall:
	var who := ctx.actor as Node3D if ctx != null else null
	if who == null or not who.is_inside_tree():
		return null
	var ball: FieldBall = FieldBall.find(who.get_tree())
	if ball == null or ball.dead or not ball.in_front_of(who.global_position, facing_yaw(ctx)):
		return null
	return ball


## A bank in front: the unit ahead stands `AXE_BANK_GX` above the player's feet.
static func axe_hits_bank(ctx: InteractionContext) -> bool:
	var grid: WorldGrid = _grid(ctx)
	if grid == null or ctx == null or ctx.actor == null or not ("layout" in ctx.world):
		return false
	var layout: WorldData = ctx.world.get("layout") as WorldData
	var cell: Vector2i = facing_cell(ctx)
	if layout == null or not grid.is_in_bounds(cell):
		return false
	var y: float = FieldCollision.ground_y(layout, cell)
	return y - (ctx.actor as Node3D).global_position.y >= AXE_BANK_GX * FieldCatalog.GX_TO_METERS


## `Player_actor_ChangeItemNo_axe_common`: the hit wears the axe in hand (`AxeWear`); when it
## gives out, the player plays `BROKEN_AXE`.
static func wear_axe(ctx: InteractionContext, reflected: bool) -> void:
	if ctx == null or ctx.inventory == null or not AxeWear.is_worn_axe(ctx.inventory.equipment_id):
		return
	if AxeWear.apply(ctx.inventory, reflected, ctx.actor) == &"" and ctx.actor != null and ctx.actor.has_method("broken_axe"):
		ctx.actor.call("broken_axe")


static func scoop_outcome(ctx: InteractionContext) -> Scoop:
	var grid: WorldGrid = _grid(ctx)
	if grid == null:
		return Scoop.AIR
	var cell: Vector2i = facing_cell(ctx)
	var layout: WorldData = null
	if ctx != null and ctx.world != null and "layout" in ctx.world:
		layout = ctx.world.get("layout") as WorldData
	var attr: int = FieldCollision.unit_attr_at_cell(layout, cell) if layout != null else -1
	return scoop_for(grid.terrain_at(cell), attr)


## `mFI_GetDigStatus` → `mCoBG_CheckHole` (dig) / `CheckSkySwing` (air) / anything else
## (reflect), with `Player_actor_SetSound_Reflect_scoop`'s clang. `attr` −1: terrain only.
static func scoop_for(terrain: WorldGrid.Terrain, attr: int) -> Scoop:
	if attr >= 0:
		if FieldCatalog.is_diggable_attr(attr):
			return Scoop.DIG
		if FieldCatalog.is_water_attr(attr) or FieldCatalog.is_hole_attr(attr):
			return Scoop.AIR
		if attr == ATTR_BUSH:
			return Scoop.HIT_BUSH
		if attr == ATTR_WOOD or FieldCatalog.is_wood_bridge_attr(attr):
			return Scoop.HIT_WOOD
		return Scoop.HIT_STONE
	match terrain:
		WorldGrid.Terrain.GRASS, WorldGrid.Terrain.SOIL, WorldGrid.Terrain.SAND:
			return Scoop.DIG
		WorldGrid.Terrain.WATER, WorldGrid.Terrain.CLIFF:
			return Scoop.AIR
	return Scoop.HIT_STONE


## `mFI_GetDigStatus` with the golden shovel: one dig in ten, somewhere other than the last
## spot, turns up a 100-Bell bag (`ITM_MONEY_100`) from the new hole.
static func _golden_bells(ctx: InteractionContext, cell: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not golden_finds_bells(cell, Game.golden_last_dig, rng.randi_range(0, GOLD_BELLS_CHANCE - 1)):
		Game.golden_last_dig = cell
		return
	Game.golden_last_dig = cell
	var bag: ItemData = ItemCatalog.get_item(&"money_100")
	if bag != null and ctx != null and ctx.inventory != null and ctx.inventory.add(bag, 1) == 0:
		Game.post_notice("You dug up 100 Bells!")


## `mFI_CheckDigDiffPosArea(wpos, old_pos) && RANDOM(10) == 1`.
static func golden_finds_bells(cell: Vector2i, last: Vector2i, roll: int) -> bool:
	return cell != last and roll == 1


static func facing_yaw(ctx: InteractionContext) -> float:
	if ctx == null or ctx.actor == null or not ctx.actor.has_method("facing_yaw"):
		return 0.0
	return float(ctx.actor.call("facing_yaw"))


static func _facing_point(ctx: InteractionContext, distance: float) -> Vector3:
	var origin: Vector3 = ctx.actor.global_position
	var yaw: float = 0.0
	if ctx.actor.has_method("facing_yaw"):
		yaw = float(ctx.actor.call("facing_yaw"))
	return origin + Vector3(sin(yaw), 0.0, cos(yaw)) * distance


static func _grid(ctx: InteractionContext) -> WorldGrid:
	if ctx == null or ctx.world == null:
		return null
	var value: Variant = ctx.world.get("grid")
	return value as WorldGrid


## `Get_PlayerAnimeIndex_fromItemKind_Tumble(_getup)`: axes / shovels / fans → `_a1`;
## nets / umbrellas / rods / pinwheels → `_n1`; empty hands → plain `kokeru1`.
static func tumble_clip(tool: ToolData, getup: bool) -> String:
	var held: ToolData.Kind = tool.kind if tool != null else ToolData.Kind.NONE
	match held:
		ToolData.Kind.AXE, ToolData.Kind.SHOVEL, ToolData.Kind.WATERING_CAN:
			return ANIM_KOKERU_GETUP_A if getup else ANIM_KOKERU_A
		ToolData.Kind.NET, ToolData.Kind.FISHING_ROD, ToolData.Kind.UMBRELLA:
			return ANIM_KOKERU_GETUP_N if getup else ANIM_KOKERU_N
		_:
			return ANIM_KOKERU_GETUP if getup else ANIM_KOKERU
