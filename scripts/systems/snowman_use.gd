class_name SnowmanUse
extends RefCounted

## Snowballs and snowmen on the field (`snowman_start`, `aSMAN_snowman_hit_check`,
## `aSNOWMAN_Set_PSnowman_info`, `mSN_regist_snowman_society`). Rules live in
## `SnowmanRules`; the rolling is `snowball.gd`, a standing snowman `snowman.gd`.

const BALL_SCENE := "res://scenes/world/snowball.tscn"
const SNOWMAN_SCENE := "res://scenes/world/snowman.tscn"
const EVENT := &"snowman_season"
## `make_move_actor_in_free_block` ids (`0x64`, `0x65`).
const PLACE_IDS: Array[int] = [0x64, 0x65]
## `aSMAN_FG_Position_Get`: the unit itself, then E, W, S, N, then the corners.
const FG_AROUND: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]


static func persist_id(slot: int) -> StringName:
	return StringName("snowman_%d" % slot)


## `snowman_start`: two balls, unless a snowman went up today (`SNOWMAN0/3/6` still at age 0)
## or since the last 6 AM (`mEv_snowman_born_check`).
static func should_place_balls(now_minute: int) -> bool:
	for e: Variant in Game.snowmen:
		var d: Dictionary = e
		if not d.is_empty() and int(d.get("age", 0)) == 0:
			return false
	return SnowmanRules.balls_allowed(Game.snowman_built_minute, now_minute)


static func spawn_balls(mgr: EventManager) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if mgr == null or mgr.world == null or not should_place_balls(Clock.absolute_minute()):
		return out
	for p: int in [SnowmanRules.PART_BODY, SnowmanRules.PART_HEAD]:
		var state: Dictionary = Game.snowballs.get(p, {})
		var cell := Vector2i(-1, -1)
		if not state.is_empty():
			var c: Array = state.get("cell", [])
			if c.size() == 2:
				cell = Vector2i(int(c[0]), int(c[1]))
		if cell.x < 0 or not mgr.world.grid.is_in_bounds(cell):
			cell = mgr.search_empty_unit(StringName("snowball_%d" % p), PLACE_IDS[p] + 31 * p)
			if cell.x < 0:
				continue
			state = {"cell": [cell.x, cell.y], "dist": 0.0}
			Game.snowballs[p] = state
		var ball: Node3D = spawn_ball(mgr.world, p, cell, float(state.get("dist", 0.0)))
		if ball != null:
			out.append(ball)
	return out


static func spawn_ball(world: Node, part: int, cell: Vector2i, dist: float) -> Node3D:
	if world == null or not ResourceLoader.exists(BALL_SCENE):
		return null
	var ball: Node3D = (load(BALL_SCENE) as PackedScene).instantiate() as Node3D
	ball.set("part", part)
	ball.set("move_dist", dist)
	var parent: Node = world.get_node_or_null("Objects")
	if parent == null:
		parent = world
	parent.add_child(ball)
	var grid: WorldGrid = world.get("grid") as WorldGrid
	ball.global_position = grid.cell_to_world(cell) if grid != null else Vector3.ZERO
	ball.call("_snap_ground")
	return ball


## A ball broke, sank or went into a snowman: a fresh one is placed next time.
static func ball_gone(part: int) -> void:
	Game.snowballs.erase(part)


## `aSMAN_snowman_hit_check`: body and head, both past a fifth of full size, at least one
## rolling, on an inner unit of the player's acre. Returns true when the combine starts.
static func try_combine(a: Node3D, b: Node3D) -> bool:
	var pa: int = int(a.get("part"))
	var pb: int = int(b.get("part"))
	var na: float = float(a.call("normalized"))
	var nb: float = float(b.call("normalized"))
	if not SnowmanRules.can_combine(pa, na, pb, nb):
		return false
	var sa: float = float(a.call("speed"))
	var sb: float = float(b.call("speed"))
	if sa <= 0.0 and sb <= 0.0:
		return false
	var world := World.find(a.get_tree())
	var player := Player.find(a.get_tree())
	if world == null or world.grid == null:
		return false
	var head: Node3D = a if sa >= sb else b
	var body: Node3D = b if head == a else a
	var body_cell: Vector2i = world.grid.world_to_cell(body.global_position)
	var unit := Vector2i(posmod(body_cell.x, 16), posmod(body_cell.y, 16))
	if unit.x == 0 or unit.x == 15 or unit.y == 0 or unit.y == 15:
		return false
	if player != null and world.grid.world_to_cell(player.global_position) / 16 != body_cell / 16:
		return false
	var nh: float = float(head.call("normalized"))
	var nbody: float = float(body.call("normalized"))
	var res: int = SnowmanRules.result(SnowmanRules.actor_scale(nh), SnowmanRules.actor_scale(nbody))
	var center: Vector3 = world.grid.cell_to_world(body_cell)
	center.y = body.global_position.y
	## Ball nodes sit on the ground; the head's centre lands 0.6 × (r_head + r_body) above the
	## body's centre (`oc_pos.y += height * 0.6`).
	var rh: float = SnowmanRules.radius_m(nh)
	var rb: float = SnowmanRules.radius_m(nbody)
	var top: float = center.y + rb + (rh + rb) * 0.6 - rh
	var on_built := func() -> void: _built(world, head, body, nh, nbody, res, body_cell)
	if player != null:
		player.set_busy(true)
	body.call("begin_combine", false, center, center.y, Callable())
	head.call("begin_combine", true, center, top, on_built)
	## `aSMAN_process_combine_head_jump_init`: the grade, the gift, the date, the quest.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if res == SnowmanRules.Result.PERFECT:
		send_present(rng)
	Game.snowman_built_minute = Clock.absolute_minute()
	Game.quests.note_snowman(body_cell / 16, Game.residents, true)
	ball_gone(SnowmanRules.PART_BODY)
	ball_gone(SnowmanRules.PART_HEAD)
	return true


static func _built(world: World, head: Node3D, body: Node3D, nh: float, nb: float, res: int, cell: Vector2i) -> void:
	var player := Player.find(world.get_tree()) if world != null else null
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var slot: int = SnowmanRules.free_slot(Game.snowmen)
	var at: Vector2i = fg_cell(world, cell)
	if slot >= 0 and at.x >= 0:
		Game.snowmen[slot] = {"head": nh, "body": nb, "score": res, "cell": [at.x, at.y], "age": 0}
	var snowman: Node3D = spawn_snowman(world, slot if at.x >= 0 else -1, at if at.x >= 0 else cell, nh, nb, res)
	if is_instance_valid(head):
		head.queue_free()
	if is_instance_valid(body):
		body.queue_free()
	if player != null:
		player.set_busy(false)
	if snowman != null and snowman.has_method("say"):
		snowman.call("say", SnowmanRules.combine_msg(res, rng), player)


## `aSMAN_FG_Position_Get`: the first unit around that takes a standing snowman.
static func fg_cell(world: World, cell: Vector2i) -> Vector2i:
	if world == null or world.grid == null:
		return Vector2i(-1, -1)
	for o: Vector2i in FG_AROUND:
		var c: Vector2i = cell + o
		if world.grid.can_place(c, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT):
			return c
	return Vector2i(-1, -1)


static func spawn_snowman(world: Node, slot: int, cell: Vector2i, head: float, body: float, score: int) -> Node3D:
	if world == null or not ResourceLoader.exists(SNOWMAN_SCENE):
		return null
	var grid: WorldGrid = world.get("grid") as WorldGrid
	if grid == null:
		return null
	var node: Node3D = (load(SNOWMAN_SCENE) as PackedScene).instantiate() as Node3D
	node.set("slot", slot)
	node.set("head", head)
	node.set("body", body)
	node.set("score", score)
	var parent: Node = world.get_node_or_null("Objects")
	if parent == null:
		parent = world
	parent.add_child(node)
	var pos: Vector3 = grid.cell_to_world(cell)
	var layout: WorldData = world.get("layout") as WorldData
	if layout != null:
		pos.y = FieldCollision.ground_y(layout, cell)
	node.global_position = pos
	if slot >= 0:
		var pid: StringName = persist_id(slot)
		if not grid.is_occupied(cell):
			grid.place(pid, cell, Vector2i(1, 1), WorldGrid.Facing.SOUTH, WorldGrid.PlaceKind.PLANT)
		node.set("occupant_id", pid)
	return node


## The snowmen still standing, back on the field.
static func restore(world: Node) -> void:
	for i: int in Game.snowmen.size():
		var e: Dictionary = Game.snowmen[i]
		if e.is_empty():
			continue
		var c: Array = e.get("cell", [])
		if c.size() != 2:
			Game.snowmen[i] = {}
			continue
		spawn_snowman(world, i, Vector2i(int(c[0]), int(c[1])), float(e.get("head", 0.0)), float(e.get("body", 0.0)), int(e.get("score", 3)))


## `mSN_ClearSnowman` + `mQst_BackSnowman`: knocked down.
static func knocked_down(slot: int, cell: Vector2i, world: Node) -> void:
	if slot >= 0 and slot < Game.snowmen.size():
		Game.snowmen[slot] = {}
	var grid: WorldGrid = world.get("grid") as WorldGrid if world != null else null
	if grid != null and slot >= 0:
		grid.remove(persist_id(slot))
	Game.quests.note_snowman(cell / 16, Game.residents, false)


## `aSMAN_SendPresentMail`: the post office holds it until the next delivery.
static func send_present(rng: RandomNumberGenerator) -> bool:
	var collected := func(id: StringName) -> bool: return Game.catalog != null and Game.catalog.has(id)
	var gift: Dictionary = SnowmanRules.present(rng, collected)
	var item: ItemData = ItemCatalog.get_item(gift["id"] as StringName)
	var name: String = item.display_name if item != null else String(gift["id"])
	var text: Dictionary = MailBank.letter(int(gift["mail"]), Game.player_name, {0: name})
	var mail := MailData.new()
	mail.header = text["header"]
	mail.body = text["body"]
	mail.footer = text["footer"]
	mail.present_item_id = gift["id"]
	mail.font = MailData.LetterFont.RECV_PRESENT
	mail.sender_type = MailData.NameType.NPC
	mail.recipient_type = MailData.NameType.PLAYER
	mail.recipient_name = Game.player_name
	mail.paper_type = 12
	return Game.post != null and Game.post.receipt_mail(mail)
