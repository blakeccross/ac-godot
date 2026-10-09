class_name DebugConsole
extends RefCounted

## Slash-command parser for the play HUD debug overlay (weather, season, give, …).
## Not an autoload — the overlay owns one instance. Logic stays testable without UI.

const COMMANDS: PackedStringArray = [
	"help", "weather", "season", "give", "time", "bells", "house", "event", "fortune", "bug", "shop",
	"balloon", "rainbow", "tune", "board", "map", "abd", "catalog", "sting", "pitfall", "exercise", "resetti", "weeds", "town", "moneyrock", "mushrooms", "shells", "snowballs", "snowman", "tan", "diary", "fengshui", "birthday", "mom", "calendar", "treasure", "golden", "wisp", "blanca", "meteor", "signboard", "equip", "axebreak", "release", "throwfish", "mailbox", "twirl", "manpu", "digup", "ball", "xmas", "reflect", "drop", "bridge", "clear"
]
const SHOP_ARGS: PackedStringArray = ["status", "sales", "visitor", "restock", "turnips"]
const EVENT_ARGS: PackedStringArray = ["list", "start", "stop", "goto", "special"]
const HOUSE_ARGS: PackedStringArray = ["size", "basement", "build", "loan", "statue", "goki", "neglect", "roof"]
const HOUSE_SIZES: PackedStringArray = ["small", "medium", "large", "upper"]
const WEATHER_KINDS: PackedStringArray = ["clear", "rain", "snow", "sakura"]
const INTENSITY_NAMES: PackedStringArray = ["none", "light", "normal", "heavy"]
const SEASON_ARGS: PackedStringArray = ["spring", "summer", "autumn", "fall", "winter", "next"]

var history: PackedStringArray = []


func execute(raw: String) -> String:
	var line: String = raw.strip_edges()
	if line.begins_with("/"):
		line = line.substr(1).strip_edges()
	if line.is_empty():
		return ""
	_push_history(raw.strip_edges())
	var parts: PackedStringArray = line.split(" ", false)
	if parts.is_empty():
		return ""
	var cmd: String = String(parts[0]).to_lower()
	var args: PackedStringArray = parts.slice(1)
	match cmd:
		"help", "?":
			return _cmd_help()
		"weather":
			return _cmd_weather(args)
		"season":
			return _cmd_season(args)
		"give":
			return _cmd_give(args)
		"equip":
			## Give a tool and hold it (`equip red_pinwheel`).
			var eq_msg: String = _cmd_give(args)
			var eq_id := StringName(String(args[0]).to_lower()) if not args.is_empty() else &""
			for i: int in Inventory.POCKET_SLOTS:
				var eq_slot: InventorySlot = Game.inventory.slot_at(i)
				if eq_slot != null and not eq_slot.is_empty() and eq_slot.item.item_id == eq_id:
					return "%s Equipped: %s." % [eq_msg, Game.inventory.equip_slot(i)]
			return eq_msg
		"bridge":
			## `bridge` sends Tortimer to the river for the second bridge; `bridge build` puts it
			## up now in the first river acre with a spot.
			var br_tree := Engine.get_main_loop() as SceneTree
			var br_world: World = World.find(br_tree) if br_tree != null else null
			if br_world == null:
				return "No field here."
			if not args.is_empty() and String(args[0]) == "build":
				var br_blocks: Array[Vector2i] = SecondBridge.blocks(br_world.layout)
				if br_blocks.is_empty():
					return "No bridge spot in this town."
				var br_today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
				SecondBridge.order(br_blocks[br_blocks.size() - 1], br_today - 1)
				SecondBridge.build_if_due(br_today, Clock.hour)
				SecondBridge.restore(br_world, br_world.layout, br_world.grid)
				return "Bridge built in acre %s." % br_blocks[br_blocks.size() - 1]
			SecondBridge.note_day(EventDates.ordinal(Clock.year, Clock.month, Clock.day))
			Game.events.force(&"soncho_bridge_make")
			_sync_events()
			return "Tortimer is by the river (%d acres with a bridge spot)." % SecondBridge.blocks(br_world.layout).size()
		"drop":
			## Lay an item on the unit in front of the player (`drop turnips_10`), as dropping does.
			var dr_tree := Engine.get_main_loop() as SceneTree
			var dr_world: Node = World.find(dr_tree) if dr_tree != null else null
			var dr_player: Node3D = Player.find(dr_tree) if dr_tree != null else null
			if dr_world == null or dr_player == null or args.is_empty():
				return "Usage: drop <item_id> (outdoors)."
			var dr_ctx := InteractionContext.new()
			dr_ctx.actor = dr_player
			dr_ctx.world = dr_world
			var dr_grid: WorldGrid = dr_world.get("grid") as WorldGrid
			var dr_front: Vector2i = ToolUse.facing_cell(dr_ctx)
			var dr_cell: Vector2i = FieldItems.drop_cell(dr_grid, dr_front, dr_front - dr_grid.world_to_cell(dr_player.global_position))
			if dr_cell.x < 0 or FieldItems.put(dr_world, dr_cell, StringName(String(args[0]).to_lower())) == null:
				return "Can't drop here."
			return "Dropped %s at %s." % [args[0], dr_cell]
		"reflect":
			## The shovel bouncing off something hard: the step back and the impact stars.
			var rf_tree := Engine.get_main_loop() as SceneTree
			var rf_player := rf_tree.get_first_node_in_group(Player.GROUP) as Player if rf_tree != null else null
			if rf_player == null:
				return "No player in this scene."
			var rf_ctx := InteractionContext.new()
			rf_ctx.actor = rf_player
			rf_ctx.world = World.find(rf_tree)
			ToolUse._reflect_scoop_fx(rf_ctx)
			return "Bounced."
		"xmas":
			## Walk up to a tree with December lights (Dec 10–25).
			var xm_tree := Engine.get_main_loop() as SceneTree
			var xm_player := xm_tree.get_first_node_in_group(Player.GROUP) as Player if xm_tree != null else null
			if xm_player == null:
				return "No player in this scene."
			for xm_node: Node in xm_tree.get_nodes_in_group("plant"):
				if xm_node.find_child("XmasLights", true, false) != null:
					var xm_pos: Vector3 = (xm_node as Node3D).global_position
					xm_player.global_position = xm_pos + Vector3(0.0, 0.0, 2.5)
					return "Lit tree at %s." % xm_pos
			return "No lit trees."
		"ball":
			## Bring the town's ball in front of the player (`ball`), or kick it (`ball kick`).
			var bl_tree := Engine.get_main_loop() as SceneTree
			var bl_player := bl_tree.get_first_node_in_group(Player.GROUP) as Player if bl_tree != null else null
			var bl_ball: FieldBall = FieldBall.find(bl_tree)
			if bl_player == null or bl_ball == null:
				return "No ball here."
			var bl_yaw: float = bl_player.facing_yaw()
			if not args.is_empty() and String(args[0]) == "kick":
				bl_ball.kick(Vector2(sin(bl_yaw), cos(bl_yaw)), Vector2(sin(bl_yaw), cos(bl_yaw)) * 7.5)
				return "Kicked."
			bl_ball.in_hole = false
			bl_ball.dead = false
			bl_ball.global_position = bl_player.global_position + Vector3(sin(bl_yaw), 0.0, cos(bl_yaw)) * 2.0
			bl_ball.call("_snap_ground")
			return "Ball at %s." % bl_ball.global_position
		"digup":
			## Play the dig-up report for an item (`digup conch`), or the loan cheer (`digup paid`).
			var du_tree := Engine.get_main_loop() as SceneTree
			var du_player := du_tree.get_first_node_in_group(Player.GROUP) as Player if du_tree != null else null
			if du_player == null:
				return "No player in this scene."
			if not args.is_empty() and String(args[0]) == "paid":
				Game.complete_payment = Game.PAYMENT_HOUSE
				du_player.run_complete_payment()
				return "Debt paid."
			var du_item := StringName(String(args[0]) if not args.is_empty() else "conch")
			du_player.run_dig_get(du_item, true, Vector2i(-1, -1), null)
			return "Dug up %s." % du_item
		"throwfish":
			## `throwfish [fish id]`: stand at the nearest bank facing the water and let a fish go.
			var tf_tree := Engine.get_main_loop() as SceneTree
			var tf_player := Player.find(tf_tree) if tf_tree != null else null
			var tf_world := World.find(tf_tree) if tf_tree != null else null
			if tf_player == null or tf_world == null:
				return "No field."
			var tf_fish := ItemCatalog.get_item(StringName(str(args[0])) if args.size() >= 1 else &"crucian_carp") as FishData
			if tf_fish == null:
				return "No such fish."
			var tf_is_water := func(at: Vector3) -> bool:
				var attr: int = FieldCollision.unit_attr_at(tf_world.layout, tf_world.grid, at)
				return attr >= 0 and FieldCatalog.is_water_attr(attr)
			var tf_cells: Array[Vector2i] = []
			for body: WaterBodies.Body in tf_world.fish.bodies:
				tf_cells.append_array(body.cells)
			var tf_from: Vector2i = tf_world.grid.world_to_cell(tf_player.global_position)
			tf_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(tf_from) < b.distance_squared_to(tf_from))
			for cell: Vector2i in tf_cells.slice(0, 80):
				for dir: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
					var stand: Vector3 = tf_world.grid.cell_to_world(cell - dir * 2)
					if tf_is_water.call(stand):
						continue
					var yaw: float = atan2(float(dir.x), float(dir.y))
					var water: Variant = CreatureRelease.search_water(tf_is_water, stand, yaw)
					if water == null:
						continue
					var ground: float = FieldCollision.ground_y_at(tf_world.layout, tf_world.grid, stand)
					stand.y = ground if FieldCollision.has_floor(ground) else tf_player.global_position.y
					tf_player.global_position = stand
					tf_player.set_facing(yaw)
					var w: Vector3 = water as Vector3
					w.y = tf_world.fish.surface_at(w)
					tf_player.release_from_pocket(tf_fish, w)
					return "Threw %s." % tf_fish.display_name
			return "No bank found."
		"mailbox":
			## Walk up to the player's own mailbox and check it, as the A button would.
			var mb_tree := Engine.get_main_loop() as SceneTree
			var mb_player := Player.find(mb_tree) if mb_tree != null else null
			if mb_player == null:
				return "No player."
			for node: Node in mb_tree.get_nodes_in_group("interactable"):
				if node.has_method("stand_spot") and bool(node.call("is_owned")):
					var mb_box := node as Node3D
					mb_player.global_position = mb_box.global_position + Vector3(0.3, 0.0, 1.6)
					var mb_ctx := InteractionContext.new()
					mb_ctx.actor = mb_player
					mb_box.call("interact", Interaction.of(Interaction.READ, "Check mailbox"), mb_ctx)
					return "Checking the mailbox."
			return "No mailbox."
		"twirl":
			## The umbrella twirl's spray at the player (`ef_kasamizu`; drops only in rain).
			var tw_player := Player.find(Engine.get_main_loop() as SceneTree)
			if tw_player == null:
				return "No player."
			StepFx.umbrella_spray(tw_player.global_position, tw_player.facing_yaw())
			return "Twirled."
		"manpu":
			## `manpu <clip|code>`: the villager nearest the camera reacts as if a talk line
			## called for it.
			var mp_tree := Engine.get_main_loop() as SceneTree
			var mp_cam: Camera3D = mp_tree.root.get_viewport().get_camera_3d() if mp_tree != null else null
			if mp_cam == null or args.is_empty():
				return "Usage: manpu <clip|code>"
			var mp_best: Node3D = null
			for v: Node in mp_tree.get_nodes_in_group("villagers"):
				if not (v is Node3D and v.has_method("cue_manpu") and (v as Node3D).is_visible_in_tree()):
					continue
				var mp_d: float = (v as Node3D).global_position.distance_to(mp_cam.global_position)
				if mp_best == null or mp_d < mp_best.global_position.distance_to(mp_cam.global_position):
					mp_best = v as Node3D
			if mp_best == null:
				return "No villager."
			## Reactions only come in a talk: hold the villager still as a talk would.
			var mp_ai: Variant = mp_best.get("ai")
			if mp_ai != null and not mp_ai.is_talking():
				mp_ai.begin_talk()
			mp_best.call("cue_manpu", str(args[0]))
			return "%s: %s" % [mp_best.name, NpcManpu.clip_for(str(args[0]))]
		"axebreak":
			## Hold a seventh-stage axe one hit from breaking, and break it now (`BROKEN_AXE`).
			_cmd_give(["axe_use_7"])
			for i: int in Inventory.POCKET_SLOTS:
				var ab_slot: InventorySlot = Game.inventory.slot_at(i)
				if ab_slot != null and not ab_slot.is_empty() and ab_slot.item.item_id == &"axe_use_7":
					Game.inventory.equip_slot(i)
			AxeWear.damage = AxeWear.LIMIT - 1
			var ab_tree := Engine.get_main_loop() as SceneTree
			var ab_player: Node = Player.find(ab_tree) if ab_tree != null else null
			if ab_player != null and AxeWear.apply(Game.inventory, false, ab_player) == &"":
				ab_player.call("broken_axe")
				return "The axe broke."
			return "Axe at stage 7, one swing from breaking."
		"release":
			## Watch something drift off up and to the left, as after letting a bug go.
			var rl_tree := Engine.get_main_loop() as SceneTree
			var rl_player := Player.find(rl_tree) if rl_tree != null else null
			if rl_player == null:
				return "No player."
			## Parented to the player so it keeps its offset wherever the player is put.
			var mark := Node3D.new()
			rl_player.add_child(mark)
			var rl_yaw: float = rl_player.facing_yaw()
			## `release [turn° [height m]]`: where the thing goes, from the player's facing.
			var rl_turn: float = deg_to_rad(float(args[0]) if args.size() >= 1 else 50.0)
			var rl_up: float = float(args[1]) if args.size() >= 2 else 3.0
			mark.position = Vector3(sin(rl_yaw + rl_turn), 0.0, cos(rl_yaw + rl_turn)) * 2.5 + Vector3(0.0, rl_up, 0.0)
			rl_player.call("_watch_release", mark, HeldTool.find_skeleton(rl_player.get("_mesh")))
			return "Watching."
		"time":
			return _cmd_time(args)
		"bells":
			return _cmd_bells(args)
		"house":
			return _cmd_house(args)
		"event", "events":
			return _cmd_event(args)
		"fortune", "destiny":
			return _cmd_fortune(args)
		"bug", "insect":
			return _cmd_bug(args)
		"shop":
			return _cmd_shop(args)
		"balloon":
			return _cmd_balloon(args)
		"rainbow":
			## Show the waterfall rainbow now (`rainbow_opacity` 1), or `rainbow off`.
			var on: bool = args.is_empty() or String(args[0]).to_lower() != "off"
			Game.rainbow.opacity = 1.0 if on else 0.0
			return "Rainbow %s." % ("on" if on else "off")
		"tune":
			return _cmd_tune(args)
		"map":
			## Open the town map (`mSM_OVL_MAP`) as the sight-map board does.
			var map_tree := Engine.get_main_loop() as SceneTree
			var map_ui: Node = map_tree.get_first_node_in_group("map_ui") if map_tree != null else null
			if map_ui == null:
				return "No map UI in this scene."
			map_ui.call("open", true)
			return "Map open."
		"catalog":
			## Open the catalog, optionally on page 0-8 (1 wallpaper, 2 carpet).
			var clg_tree := Engine.get_main_loop() as SceneTree
			var clg: Node = clg_tree.get_first_node_in_group("catalog_ui") if clg_tree != null else null
			if clg == null:
				return "No catalog UI in this scene."
			if args.size() >= 2 and String(args[1]).to_lower() == "fill" and Game.catalog != null:
				## Every wallpaper and carpet as if collected.
				for kind: String in ["wall", "carpet"]:
					for i: int in 67:
						var goods: StringName = FtrCatalog.goods_id(kind, i)
						if goods != &"":
							Game.catalog.record(goods)
			clg.call("open")
			if not args.is_empty() and String(args[0]).is_valid_int():
				clg.call("show_page", int(args[0]))
			return "Catalog open."
		"abd":
			## Open the post office bank terminal (`mSM_OVL_BANK`).
			var abd_tree := Engine.get_main_loop() as SceneTree
			var abd: Node = abd_tree.get_first_node_in_group("bank_ui") if abd_tree != null else null
			if abd == null:
				return "No bank UI in this scene."
			abd.call("open")
			return "Bank terminal open."
		"board":
			## Open the community board's posts (`mSM_OVL_NOTICE`).
			var tree := Engine.get_main_loop() as SceneTree
			var ui: Node = tree.get_first_node_in_group("notice_ui") if tree != null else null
			if ui == null:
				return "No notice board UI in this scene."
			ui.call("open")
			return "%d posts on the board." % Game.notice_board.count()
		"sting":
			## Bee sting: `sting` plays it, `sting off` / `sting on` sets the swollen face,
			## `sting swarm` lets a swarm loose.
			var sting_tree := Engine.get_main_loop() as SceneTree
			var mode: String = String(args[0]).to_lower() if not args.is_empty() else ""
			if mode == "off" or mode == "on":
				Game.bee_swell = mode == "on"
				Game.bee_greeted.clear()
				Game.face_changed.emit()
				return "Face %s." % ("swollen" if Game.bee_swell else "normal")
			var who := sting_tree.get_first_node_in_group(Player.GROUP) as Player if sting_tree != null else null
			if who == null:
				return "No player in this scene."
			if mode == "swarm":
				BeeSwarm.spawn(who.get_parent(), who.global_position + Vector3(4.0, 2.5, 4.0), who)
				return "A swarm is after you."
			if mode == "mosquito":
				who.run_stung_mosquito()
				return "Itchy."
			PlayerSe.bee_sting(who)
			who.run_stung_bee()
			return "Ouch."
		"town":
			## The town assessment now (`mFAs_GetFieldRank_Condition`); `town perfect` also sets
			## fifteen perfect days so the well's spirit can come.
			var tw_tree := Engine.get_main_loop() as SceneTree
			var tw_world := World.find(tw_tree) if tw_tree != null else null
			if tw_world == null:
				return "The assessment needs the outdoor field."
			if not args.is_empty() and String(args[0]).to_lower() == "perfect":
				Game.perfect_streak = TownAssessment.PERFECT_STREAK_MAX
				Game.perfect_streak_day = Clock.day_number()
			var r: Dictionary = Game.rate_town(tw_world)
			return "Rank %d (score %d: %d perfect, %d good acres); condition %d at %s; trees %d, flowers %d, weeds %d, trash %d; streak %d." % [
				int(r["rank"]), int(r["score"]), int(r["perfect"]), int(r["good"]), int(r["condition"]),
				r["block"], int(r["trees"]), int(r["flowers"]), int(r["weeds"]), int(r["dust"]), Game.perfect_streak,
			]
		"moneyrock":
			## Where today's money rock is (`moneyrock new` picks another now).
			var mr_tree := Engine.get_main_loop() as SceneTree
			var mr_world := World.find(mr_tree) if mr_tree != null else null
			if mr_world == null:
				return "The money rock needs the outdoor field."
			if not args.is_empty() and String(args[0]).to_lower() == "new":
				Game.money_rock = ""
				Game.money_rock_day = -1
				var mr_rng := RandomNumberGenerator.new()
				mr_rng.randomize()
				MoneyRock.renew(mr_world, mr_rng, Clock.day_number())
			if Game.money_rock == "":
				return "No money rock today."
			var mr_rocks: Dictionary = MoneyRock.field_rocks(mr_world)
			return "Money rock: %s in acre %s." % [Game.money_rock, mr_rocks.get(StringName(Game.money_rock), "?")]
		"fengshui":
			## The house's feng shui now (`mHsRm_GetHuusuiRoom`) and Nook's tier odds from it.
			Game.refresh_feng_shui()
			var fs_cut: Vector2i = ShopGoods.tier_cutoffs(Game.goods_power)
			return "Money power %d, goods power %d (Nook: rare %d%%, uncommon %d%%)." % [
				Game.money_power, Game.goods_power, fs_cut.x, fs_cut.y - fs_cut.x]
		"wisp":
			## The Wisp's night: `wisp` brings him out, `wisp found` as if he had been found,
			## `wisp spirits 5` puts spirits in the pockets.
			var wi_state: Dictionary = WispEvent.state()
			var wi_sub: String = String(args[0]) if not args.is_empty() else ""
			if wi_sub == "found":
				wi_state["found"] = true
				wi_state["active"] = true
				return "Wisp found; spirits in acres %s." % [wi_state.get("acres", [])]
			if wi_sub == "spirits":
				var wi_n: int = clampi(int(args[1]) if args.size() > 1 else WispEvent.SPIRITS, 1, WispEvent.SPIRITS)
				var wi_bug: ItemData = BugCatalog.get_by_type(WispEvent.TYPE_SPIRIT)
				if wi_bug == null or Game.inventory.add(wi_bug, wi_n) != 0:
					return "No room for spirits."
				return "%d spirit(s) in the pockets." % wi_n
			Game.events.ghost_tonight = true
			Game.events.force(&"ghost")
			_sync_events()
			return "The Wisp is out tonight."
		"blanca":
			## Blanca in town with a test face (a smile) from "Tester".
			var bl_face := MaskCat.blank_face()
			for bl_i: int in 32:
				bl_face.pixels[8 * 32 + bl_i] = 1
				bl_face.pixels[22 * 32 + bl_i] = 1
				bl_face.pixels[bl_i * 32 + 8] = 4
				bl_face.pixels[bl_i * 32 + 23] = 4
			MaskCat.store(bl_face, "Tester", EventDates.ordinal(Clock.year, Clock.month, Clock.day))
			Game.events.force(&"mask_npc")
			_sync_events()
			return "Blanca is in town."
		"golden":
			## Hold up a golden tool (`golden net|rod|axe`), as after Tortimer's visit or the well.
			var go_ids: Dictionary = {"net": &"golden_net", "rod": &"golden_fishing_rod", "axe": &"golden_axe"}
			var go_id: StringName = go_ids.get(String(args[0]) if not args.is_empty() else "rod", &"golden_fishing_rod")
			var go_tree := Engine.get_main_loop() as SceneTree
			var go_player := Player.find(go_tree) as Player if go_tree != null else null
			if go_player == null:
				return "No player here."
			go_player.get_golden_item(go_id)
			return "Holding up %s." % go_id
		"treasure":
			## A villager buries something now and posts where (`mNtc_check_treasure`).
			var tr_tree := Engine.get_main_loop() as SceneTree
			var tr_world: World = World.find(tr_tree) if tr_tree != null else null
			if tr_world == null:
				return "No field here."
			var tr_rng := RandomNumberGenerator.new()
			tr_rng.randomize()
			var tr_cell: Vector2i = BuriedTreasure.check(tr_world, tr_rng, true)
			if tr_cell.x < 0:
				return "Nothing buried."
			var tr_rec: Dictionary = BuriedUse.record(BuriedUse.persist_id(tr_cell))
			return "%s buried at %s (acre %s): %s" % [tr_rec.get("item_id", "?"), tr_cell,
				VillagerWalk.block_from_cell(tr_cell), str(Game.notice_board.posts[-1]["text"]).replace("\n", " ")]
		"calendar":
			## The calendar (`calendar day 31` opens on a day); `calendar played 2026-9-14` /
			## `calendar tortimer 2026-9-14` mark a day.
			var ca_tree := Engine.get_main_loop() as SceneTree
			if args.size() > 1 and String(args[0]) == "day":
				var ca_day_ui: Node = ca_tree.get_first_node_in_group("calendar_ui") if ca_tree != null else null
				if ca_day_ui == null:
					return "No calendar here."
				ca_day_ui.call("open_on_day", int(args[1]))
				return "Calendar on day %s." % args[1]
			if args.size() > 1:
				var ca_d: PackedStringArray = String(args[1]).split("-")
				if ca_d.size() != 3:
					return "Date as Y-M-D."
				var ca_n: int = EventDates.ordinal(int(ca_d[0]), int(ca_d[1]), int(ca_d[2]))
				var ca_today: int = EventDates.ordinal(Clock.year, Clock.month, Clock.day)
				CalendarBook.trim(Game.calendar, ca_today)
				var ca_key: String = "events" if String(args[0]) == "tortimer" else "played"
				if not (Game.calendar[ca_key] as Array).has(ca_n):
					(Game.calendar[ca_key] as Array).append(ca_n)
				return "Marked %s as %s." % [args[1], ca_key]
			var ca_ui: Node = ca_tree.get_first_node_in_group("calendar_ui") if ca_tree != null else null
			if ca_ui == null:
				return "No calendar here."
			ca_ui.call("open")
			return "Calendar."
		"mom":
			## Mom writes now: today's dated letter if there is one, else an everyday letter
			## (`mom 0x151` for a given one).
			var mm_rng := RandomNumberGenerator.new()
			mm_rng.randomize()
			var mm_pick: Dictionary = MotherMail.dated(Clock.month, Clock.day, VillagerTalkManager.birthday(),
				MotherMail.holiday(Clock.year, Clock.month, Clock.day), mm_rng)
			if not args.is_empty():
				var mm_no: int = String(args[0]).hex_to_int() if String(args[0]).begins_with("0x") else int(args[0])
				var mm_idx: int = mm_no - MotherMail.MSG_NORMAL
				mm_pick = {"msg": mm_no, "present": MotherMail.normal_present(mm_idx, mm_rng) if mm_idx >= 0 and mm_idx < MotherMail.NORMAL_COUNT else &""}
			elif mm_pick.is_empty():
				var mm_left: Array[int] = MotherMail.normal_left(Game.mother_mail)
				var mm_n: int = mm_left[mm_rng.randi_range(0, mm_left.size() - 1)] if not mm_left.is_empty() else 0
				mm_pick = {"msg": MotherMail.MSG_NORMAL + mm_n, "present": MotherMail.normal_present(mm_n, mm_rng)}
			var mm_mail: MailData = MotherMail.letter(int(mm_pick["msg"]), StringName(mm_pick["present"]),
				MotherMail.paper(Clock.month, Clock.day, VillagerTalkManager.birthday()), Game.player_name)
			if mm_mail == null or not Game.deliver_to_mailbox(mm_mail):
				return "Mom couldn't write (no mail bank or the mailbox is full)."
			var mm_tree := Engine.get_main_loop() as SceneTree
			var mm_reader: Node = mm_tree.get_first_node_in_group("letter_reader_ui") if mm_tree != null else null
			if mm_reader != null:
				mm_reader.call("open", mm_mail)
			return "Letter 0x%X from Mom in the mailbox%s." % [int(mm_pick["msg"]),
				(" with %s" % mm_mail.present_item_id) if mm_mail.present_item_id != &"" else ""]
		"birthday":
			## `birthday` opens the "When's your birthday?" picker; `birthday visit [rod|net]`
			## sends the present visitor to the player now; `birthday cards` mails the cards.
			var bd_tree := Engine.get_main_loop() as SceneTree
			var bd_sub: String = String(args[0]).to_lower() if not args.is_empty() else ""
			if bd_sub == "cards":
				var bd_rng := RandomNumberGenerator.new()
				bd_rng.randomize()
				var bd_sent: int = PresentVisit.send_cards(Game.residents, Game.relationships, &"",
					Game.player_name, bd_rng, Game.deliver_to_mailbox)
				return "%d birthday card(s) sent." % bd_sent
			if bd_sub == "visit":
				var bd_kind: int = PresentVisit.Kind.BIRTHDAY
				if args.size() > 1:
					bd_kind = PresentVisit.Kind.GOLDEN_NET if String(args[1]) == "net" else PresentVisit.Kind.GOLDEN_ROD
				else:
					Game.birthday_present_npc = PresentVisit.birthday_npc(Game.residents, Game.relationships)
					if Game.birthday_present_npc == &"" and not Game.residents.resident_ids().is_empty():
						Game.birthday_present_npc = Game.residents.resident_ids()[0]
				var bd_player := Player.find(bd_tree) as Node3D if bd_tree != null else null
				var bd_world: Node = World.find(bd_tree) if bd_tree != null else null
				if bd_player == null or bd_world == null:
					return "No field here."
				var bd_yaw: float = float(bd_player.call("facing_yaw"))
				var bd_npc: Node3D = load("res://scenes/world/present_npc.gd").spawn(
					bd_world.get_node("Characters"), bd_kind, bd_player.global_position, bd_yaw)
				return "Present visit." if bd_npc != null else "Nobody to send."
			var bd_ui: Node = bd_tree.get_first_node_in_group("birthday_ui") if bd_tree != null else null
			if bd_ui == null:
				return "No birthday screen here."
			bd_ui.call("open")
			return "Birthday: pick a date."
		"diary":
			## Open the diary on a month (`diary 4`), or write a line into one first
			## (`diary 4 Went fishing all day.`).
			var di_tree := Engine.get_main_loop() as SceneTree
			var di_ui: Node = di_tree.get_first_node_in_group("diary_ui") if di_tree != null else null
			if di_ui == null:
				return "No diary screen here."
			var di_month: int = clampi(int(args[0]), 1, 12) if not args.is_empty() and String(args[0]).is_valid_int() else Clock.month
			if args.size() > 1:
				Game.diary[di_month] = DiaryOverlay.clip(" ".join(args.slice(1)))
			di_ui.call("open", di_month)
			return "Diary: month %d." % di_month
		"tan":
			## Set the sunburn rank 0–8 (`mPr_sunburn_c`) and repaint the face.
			if args.is_empty() or not String(args[0]).is_valid_int():
				return "Tan rank %d (hold %d days)." % [int(Game.sunburn.get("rank", 0)), int(Game.sunburn.get("hold", 0))]
			Game.sunburn["rank"] = clampi(int(args[0]), 0, Sunburn.MAX_RANK)
			Game.sunburn["changed"] = Clock.day_number()
			Game.sunburn["hold"] = Sunburn.HOLD_DAYS if int(Game.sunburn["rank"]) > 0 else 0
			Game.face_changed.emit()
			return "Tan rank %d." % int(Game.sunburn["rank"])
		"snowballs":
			## The body and head balls a few units ahead of the player, at size 0–1
			## (`snowballs 0.5`; default 0.4, big enough to push).
			var sb_tree := Engine.get_main_loop() as SceneTree
			var sb_world := World.find(sb_tree) if sb_tree != null else null
			var sb_player := Player.find(sb_tree) if sb_tree != null else null
			if sb_world == null or sb_player == null:
				return "Snowballs need the outdoor field."
			var sb_collide: bool = not args.is_empty() and String(args[0]).to_lower() == "collide"
			var sb_args: PackedStringArray = args.slice(1) if sb_collide else args
			var sb_n: float = clampf(float(sb_args[0]), 0.0, 1.0) if not sb_args.is_empty() and String(sb_args[0]).is_valid_float() else 0.4
			var sb_cell: Vector2i = sb_world.grid.world_to_cell(sb_player.global_position)
			var sb_fwd := Vector3(sin(sb_player.facing_yaw()), 0.0, cos(sb_player.facing_yaw()))
			var sb_dir := Vector2i(roundi(sb_fwd.x), roundi(sb_fwd.z))
			if sb_dir == Vector2i.ZERO:
				sb_dir = Vector2i(0, 1)
			var sb_side := Vector2i(-sb_dir.y, sb_dir.x)
			SnowmanUse.spawn_ball(sb_world, SnowmanRules.PART_BODY, sb_cell + sb_dir * 2, sb_n * SnowmanRules.MOVE_DIST_MAX)
			## `snowballs collide`: the head starts against the body, rolling into it.
			var sb_gap: int = 1 if sb_collide else 3
			var sb_head: Node3D = SnowmanUse.spawn_ball(sb_world, SnowmanRules.PART_HEAD, sb_cell + sb_dir * 2 + sb_side * sb_gap, sb_n * 0.85 * SnowmanRules.MOVE_DIST_MAX)
			if sb_collide and sb_head != null:
				sb_head.set("vel", Vector2(-sb_side.x, -sb_side.y) * 1.0)
			return "Two snowballs at size %.2f%s." % [sb_n, ", the head rolling in" if sb_collide else ""]
		"snowman":
			## A finished snowman two units ahead (`snowman [score 0-3]`).
			var sm_tree := Engine.get_main_loop() as SceneTree
			var sm_world := World.find(sm_tree) if sm_tree != null else null
			var sm_player := Player.find(sm_tree) if sm_tree != null else null
			if sm_world == null or sm_player == null:
				return "A snowman needs the outdoor field."
			var sm_score: int = clampi(int(args[0]), 0, 3) if not args.is_empty() and String(args[0]).is_valid_int() else 0
			var sm_fwd := Vector3(sin(sm_player.facing_yaw()), 0.0, cos(sm_player.facing_yaw()))
			var sm_cell: Vector2i = SnowmanUse.fg_cell(sm_world, sm_world.grid.world_to_cell(sm_player.global_position + sm_fwd * 4.0))
			if sm_cell.x < 0:
				return "No room for a snowman there."
			var sm_slot: int = SnowmanRules.free_slot(Game.snowmen)
			if sm_slot >= 0:
				Game.snowmen[sm_slot] = {"head": 0.6, "body": 0.7, "score": sm_score, "cell": [sm_cell.x, sm_cell.y], "age": 0}
			SnowmanUse.spawn_snowman(sm_world, sm_slot, sm_cell, 0.6, 0.7, sm_score)
			return "Snowman (score %d) in slot %d." % [sm_score, sm_slot]
		"mushrooms":
			## Set N mushrooms under trees now (`mMsr_SetMushroomNum`), or `mushrooms clear`.
			var ms_tree := Engine.get_main_loop() as SceneTree
			var ms_world := World.find(ms_tree) if ms_tree != null else null
			if ms_world == null:
				return "Mushrooms need the outdoor field."
			var ms_rng := RandomNumberGenerator.new()
			ms_rng.randomize()
			if not args.is_empty() and String(args[0]).to_lower() == "clear":
				MushroomUse.clear(ms_world, Game.mushrooms.size(), Vector2i(-1, -1), ms_rng)
				return "Mushrooms cleared."
			var ms_n: int = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else MushroomUse.NUM
			var ms_set: int = MushroomUse.grow(ms_world, ms_n, Vector2i(-1, -1), ms_rng)
			return "%d mushrooms set (%d in town)." % [ms_set, Game.mushrooms.size()]
		"signboard":
			## Put up a signboard in front of the player, showing design slot N if given.
			var sb_tree := Engine.get_main_loop() as SceneTree
			var sb_world := World.find(sb_tree) if sb_tree != null else null
			var sb_player: Node3D = sb_tree.get_first_node_in_group("player") as Node3D if sb_tree != null else null
			if sb_world == null or sb_player == null:
				return "Signboards need the outdoor field."
			var sb_ctx := InteractionContext.new()
			sb_ctx.world = sb_world
			sb_ctx.actor = sb_player
			var sb_cell: Vector2i = ToolUse.facing_cell(sb_ctx)
			if not SignboardUse.place(sb_world, sb_cell):
				return "Can't put a signboard there."
			if not args.is_empty() and String(args[0]).is_valid_int() and Game.designs != null:
				SignboardUse.post(SignboardUse.persist_id(sb_cell), Game.designs.player[clampi(int(args[0]), 0, 7)])
				for n: Node in sb_tree.get_nodes_in_group(SignboardUse.GROUP):
					n.call("refresh_design")
			return "Signboard up at %s." % sb_cell
		"meteor":
			## Send a shooting star across the pond now (Meteor Shower only, `ef_shooting`).
			var mt_tree := Engine.get_main_loop() as SceneTree
			var mt_node: Node = mt_tree.get_first_node_in_group(MeteorShower.GROUP) if mt_tree != null else null
			if mt_node == null:
				return "No meteor shower tonight (event meteor_shower)."
			(mt_node as MeteorShower).launch_now()
			return "Shooting star."
		"shells":
			## Wash N shells up on the beach now (`mFI_SetShellWave`), with free wave units per acre.
			var sh_tree := Engine.get_main_loop() as SceneTree
			var sh_world := World.find(sh_tree) if sh_tree != null else null
			if sh_world == null:
				return "Shells need the outdoor field."
			var sh_rng := RandomNumberGenerator.new()
			sh_rng.randomize()
			var sh_n: int = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else ShellUse.FIRST_NUM
			var sh_free: Array[String] = []
			for b: Vector2i in ShellUse.beach_blocks():
				sh_free.append("%d,%d:%d" % [b.x, b.y, ShellUse.free_cells(sh_world, sh_world.grid, b).size()])
			var sh_set: int = ShellUse.wash_up(sh_world, sh_n, Vector2i(-1, -1), sh_rng)
			return "%d shells set (%d on the beach; free %s)." % [sh_set, Game.shells.size(), " ".join(sh_free)]
		"weeds":
			## Sow N weeds now (`mAGrw_SetGrass`), or `weeds clear`.
			var wd_tree := Engine.get_main_loop() as SceneTree
			var wd_world := World.find(wd_tree) if wd_tree != null else null
			if wd_world == null:
				return "Weeds need the outdoor field."
			if not args.is_empty() and String(args[0]).to_lower() == "clear":
				WeedUse.clear_all(wd_world, wd_world.grid)
				return "Weeds cleared."
			var wd_rng := RandomNumberGenerator.new()
			wd_rng.randomize()
			var wd_n: int = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else WeedUse.PER_DAY
			var grown: int = WeedUse.grow(wd_world, wd_world.grid, wd_world.layout, wd_n, wd_rng)
			return "%d weeds sown (%d in town)." % [grown, WeedUse.count()]
		"resetti":
			## Mr. Resetti now, as after reset number N (1-8; default the next one).
			var rs_tree := Engine.get_main_loop() as SceneTree
			var rs_player := rs_tree.get_first_node_in_group(Player.GROUP) as Node3D if rs_tree != null else null
			var rs_world := World.find(rs_tree) if rs_tree != null else null
			if rs_player == null or rs_world == null:
				return "Resetti needs the outdoor field."
			Game.reset_count = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else Game.reset_count + 1
			Game.reset_flag = true
			load("res://scenes/world/resetti.gd").spawn(rs_world.get_node("Characters"), rs_player)
			return "Reset #%d." % Game.reset_count
		"exercise":
			## Play radio exercise move 0-17 (`mPlayer_RADIO_EXERCISE_CMD*`).
			var ex_tree := Engine.get_main_loop() as SceneTree
			var ex_player := ex_tree.get_first_node_in_group(Player.GROUP) as Player if ex_tree != null else null
			if ex_player == null:
				return "No player in this scene."
			var ex_cmd: int = int(args[0]) if not args.is_empty() and String(args[0]).is_valid_int() else 0
			ex_player.run_radio_exercise(ex_cmd)
			return "Exercise %d." % ex_cmd
		"pitfall":
			## Bury a pitfall under the player; `pitfall auto` also struggles for you.
			var pit_tree := Engine.get_main_loop() as SceneTree
			var pit_player := pit_tree.get_first_node_in_group(Player.GROUP) as Player if pit_tree != null else null
			var pit_world := World.find(pit_tree) if pit_tree != null else null
			if pit_player == null or pit_world == null:
				return "Pitfalls need the outdoor field."
			var pit_ctx := InteractionContext.new()
			pit_ctx.world = pit_world
			pit_ctx.actor = pit_player
			var pit_at: Vector3 = pit_player.global_position
			if not args.is_empty() and String(args[0]).to_lower() == "villager":
				var best: Node3D = null
				for v: Node in pit_tree.get_nodes_in_group("villagers"):
					var v3 := v as Node3D
					if v3 != null and v3.is_visible_in_tree() and (best == null or v3.global_position.distance_to(pit_at) < best.global_position.distance_to(pit_at)):
						best = v3
				if best == null:
					return "No villager nearby."
				pit_at = best.global_position
			var pit_cell: Vector2i = pit_world.grid.world_to_cell(pit_at)
			if not HoleUse.dig(pit_ctx, pit_cell, false) or not BuriedUse.bury(pit_ctx, pit_cell, BuriedUse.PITFALL_ITEM):
				return "Can't bury a pitfall here."
			if not args.is_empty() and String(args[0]).to_lower() == "auto":
				pit_player.struggle_assist = 0.1
			return "Pitfall buried at %s." % pit_cell
		"clear":
			return "__clear__"
		_:
			return "Unknown command '%s'. Type help." % cmd


## Town tune: `tune` plays it, `tune open` opens the editor, `tune reset` restores the default.
func _cmd_tune(args: PackedStringArray) -> String:
	var sub: String = String(args[0]).to_lower() if not args.is_empty() else "play"
	match sub:
		"open":
			var tree := Engine.get_main_loop() as SceneTree
			var ui: Node = tree.get_first_node_in_group("town_tune_ui") if tree != null else null
			if ui == null:
				return "No tune editor in this scene."
			ui.call("open")
			return "Tune editor open."
		"reset":
			Game.town_tune = TownTune.default_notes()
			return "Town tune reset to the default."
	Audio.play_melody(Game.town_tune)
	return "Playing the town tune."


## Completions for the token under the cursor (Minecraft-style Tab).
func suggestions(line: String) -> PackedStringArray:
	var parsed: Dictionary = _token_at_end(line)
	var token: String = String(parsed["token"])
	var index: int = int(parsed["index"])
	var prior: PackedStringArray = parsed["prior"] as PackedStringArray
	if index == 0:
		return _filter_prefix(COMMANDS, token)
	var cmd: String = String(prior[0]).to_lower()
	if cmd.begins_with("/"):
		cmd = cmd.substr(1)
	match cmd:
		"weather":
			if index == 1:
				return _filter_prefix(WEATHER_KINDS, token)
			if index == 2:
				return _filter_prefix(INTENSITY_NAMES, token)
		"season":
			if index == 1:
				return _filter_prefix(SEASON_ARGS, token)
		"give":
			if index == 1:
				return _filter_prefix(_item_ids(), token)
		"time":
			if index == 1:
				return _filter_prefix(["+1h", "+1d", "6", "12", "18", "0"], token)
		"bells":
			if index == 1:
				return _filter_prefix(["1000", "10000", "99999"], token)
		"event", "events":
			if index == 1:
				return _filter_prefix(EVENT_ARGS, token)
			if index == 2:
				return _filter_prefix(_event_ids(String(prior[1]).to_lower()), token)
		"shop":
			if index == 1:
				return _filter_prefix(SHOP_ARGS, token)
		"house":
			if index == 1:
				return _filter_prefix(HOUSE_ARGS, token)
			if index == 2 and String(prior[1]).to_lower() == "size":
				return _filter_prefix(HOUSE_SIZES, token)
	return PackedStringArray()


## Apply Tab: fill the longest common prefix, or the sole match.
func autocomplete(line: String) -> String:
	var matches: PackedStringArray = suggestions(line)
	if matches.is_empty():
		return line
	var parsed: Dictionary = _token_at_end(line)
	var prefix: String = String(parsed["prefix"])
	var fill: String = matches[0] if matches.size() == 1 else _common_prefix(matches)
	if fill.is_empty():
		return line
	## Sole match gets a trailing space so the next arg is ready to type.
	var spacer: String = " " if matches.size() == 1 else ""
	return prefix + fill + spacer


## Replace the current token with a concrete suggestion (Tab cycle).
func fill_suggestion(line: String, suggestion: String) -> String:
	var parsed: Dictionary = _token_at_end(line)
	return String(parsed["prefix"]) + suggestion


func history_prev(current: String, index: int) -> Dictionary:
	## Returns `{text, index}` walking older entries. `index` -1 means “at live line”.
	if history.is_empty():
		return {"text": current, "index": -1}
	var next_i: int = index
	if next_i < 0:
		next_i = history.size() - 1
	else:
		next_i = maxi(next_i - 1, 0)
	return {"text": String(history[next_i]), "index": next_i}


func history_next(current: String, index: int, live: String) -> Dictionary:
	if history.is_empty() or index < 0:
		return {"text": live, "index": -1}
	var next_i: int = index + 1
	if next_i >= history.size():
		return {"text": live, "index": -1}
	return {"text": String(history[next_i]), "index": next_i}


func _push_history(line: String) -> void:
	if line.is_empty():
		return
	if not history.is_empty() and String(history[history.size() - 1]) == line:
		return
	history.append(line)
	if history.size() > 64:
		history = history.slice(history.size() - 64)


func _cmd_help() -> String:
	return "\n".join([
		"Commands:",
		"  weather <clear|rain|snow|sakura> [none|light|normal|heavy]",
		"  season <spring|summer|autumn|winter|next>",
		"  give <item_id> [count]",
		"  time [+1h|+1d|HH|HH:MM]",
		"  bells <amount>",
		"  house [size <small|medium|large|upper> | basement | build | loan <n> | statue [built [rank]] | goki [n] | neglect [days]]",
		"  event [list | start <id> | stop [id] | goto <id> | special <id>]",
		"  fortune [normal|popular|unpopular|bad_luck|money_luck|goods_luck]",
		"  bug <id> [count]  (spawn insects in front of the player)",
		"  shop [status | sales <n> | visitor | restock | turnips]",
		"  sting [on|off|mosquito]  (bee sting, set the swollen face, or a mosquito bite)",
		"  town [perfect]  (rate the town now)",
		"  weeds [n|clear]  (sow weeds now, or clear them all)",
		"  resetti [1-8]  (Mr. Resetti, as after that many resets)",
		"  exercise <0-17>  (a radio exercise move)",
		"  pitfall [auto|villager]  (bury one under the player, or the nearest villager)",
		"  clear / help",
		"Tab completes. Up/Down recall history.",
	])


## Spawns field insects a few metres ahead of the player, on the ground there, in the bug's
## first habitat — for watching a program without waiting on `aSOI_insect_set`.
## `balloon` launches a present balloon now; `balloon near` starts it just upwind of you.
func _cmd_balloon(args: PackedStringArray) -> String:
	var tree: SceneTree = Game.get_tree()
	var sky := tree.get_first_node_in_group("balloon_sky") as BalloonSky
	if sky == null:
		return "Balloons need the outdoor field."
	if sky.balloon != null:
		return "A balloon is already out."
	var b: Balloon = sky.launch()
	if args.size() > 0 and String(args[0]).to_lower() == "near":
		var player := Player.find(tree)
		if player != null:
			var yaw: float = Wind.yaw()
			b.start_near(player.global_position - Vector3(sin(yaw), 0.0, cos(yaw)) * 8.0)
	return "Balloon launched (wind %d°, power %.2f)." % [int(rad_to_deg(Wind.yaw())), Wind.power()]


func _cmd_bug(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Usage: bug <id> [count], e.g. bug grasshopper 3"
	var bug: BugData = BugCatalog.get_bug(StringName(String(args[0]).to_lower()))
	if bug == null:
		return "Unknown bug '%s'." % String(args[0])
	var tree: SceneTree = Game.get_tree()
	var world := World.find(tree)
	var player := Player.find(tree)
	if world == null or player == null or world.layout == null:
		return "Bugs need the outdoor field."
	var count: int = clampi(int(args[1]) if args.size() > 1 else 1, 1, BugField.MAX_ACTORS)
	var habitat: BugData.Habitat = (
		bug.habitats[0] as BugData.Habitat if not bug.habitats.is_empty() else BugData.Habitat.GROUND
	)
	var yaw: float = player.facing_yaw()
	var ahead := Vector3(sin(yaw), 0.0, cos(yaw))
	var side := Vector3(ahead.z, 0.0, -ahead.x)
	var spawned: int = 0
	for i: int in count:
		var at: Vector3 = player.global_position + ahead * 3.0 + side * (float(i) - (count - 1) * 0.5)
		at.y = FieldCollision.ground_y_at(world.layout, world.grid, at)
		if world.bugs.spawn(bug, habitat, at) != null:
			spawned += 1
	return "Spawned %d %s." % [spawned, bug.id]


## Today's `Private_c.destiny` — normally set by Katrina / the New Year shrine (not built
## yet); bad luck makes a full dash trip on flat ground.
func _cmd_fortune(args: PackedStringArray) -> String:
	var names: PackedStringArray = PackedStringArray(
		["normal", "popular", "unpopular", "bad_luck", "money_luck", "goods_luck"]
	)
	if args.is_empty():
		return "Fortune: %s" % names[int(Game.destiny())]
	var want: int = names.find(String(args[0]).to_lower())
	if want < 0:
		return "Unknown fortune '%s'. Use %s." % [String(args[0]), ", ".join(names)]
	Game.set_destiny(want)
	return "Fortune set to %s for today." % names[want]


func _cmd_weather(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Weather: %s (intensity %d)" % [String(Game.weather), Game.weather_intensity]
	var kind: String = String(args[0]).to_lower()
	if kind not in WEATHER_KINDS:
		return "Unknown weather '%s'. Use clear, rain, snow, or sakura." % kind
	var intensity: int = -1
	if args.size() >= 2:
		intensity = _parse_intensity(String(args[1]))
		if intensity < 0:
			return "Unknown intensity '%s'. Use none, light, normal, or heavy." % String(args[1])
	Game.set_weather(StringName(kind), intensity)
	return "Weather set to %s (intensity %d)." % [String(Game.weather), Game.weather_intensity]


func _cmd_season(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Season: %s" % Clock.season_name()
	var name: String = String(args[0]).to_lower()
	if name == "next":
		Clock.advance_season()
		return "Advanced to %s." % Clock.season_name()
	if name == "fall":
		name = "autumn"
	var season: int = _parse_season(name)
	if season < 0:
		return "Unknown season '%s'. Use spring, summer, autumn, winter, or next." % String(args[0])
	Clock.jump_to_season(season as ClockService.Season)
	return "Season set to %s (%04d-%02d-%02d)." % [Clock.season_name(), Clock.year, Clock.month, Clock.day]


func _cmd_give(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Usage: give <item_id> [count]"
	var item_id := StringName(String(args[0]).to_lower())
	var data: ItemData = ItemCatalog.get_item(item_id)
	if data == null:
		return "Unknown item '%s'." % String(args[0])
	var count: int = 1
	if args.size() >= 2:
		if not String(args[1]).is_valid_int():
			return "Count must be an integer."
		count = maxi(1, int(args[1]))
	var left: int = Game.inventory.add(data, count)
	var given: int = count - left
	if given <= 0:
		return "Pockets full — could not add %s." % String(item_id)
	if left > 0:
		return "Added %d× %s (%d did not fit)." % [given, _item_label(data), left]
	return "Added %d× %s." % [given, _item_label(data)]


func _cmd_time(args: PackedStringArray) -> String:
	if args.is_empty():
		return Clock.format_clock()
	var arg: String = String(args[0]).to_lower()
	if arg == "+1h" or arg == "+1hour":
		Clock.advance_minutes(60)
		return "Advanced 1 hour → %s" % Clock.format_clock()
	if arg == "+1d" or arg == "+1day":
		Clock.advance_minutes(60 * 24)
		return "Advanced 1 day → %s" % Clock.format_clock()
	if arg.begins_with("+") and arg.ends_with("h") and arg.substr(1, arg.length() - 2).is_valid_int():
		var hours: int = int(arg.substr(1, arg.length() - 2))
		Clock.advance_minutes(hours * 60)
		return "Advanced %dh → %s" % [hours, Clock.format_clock()]
	if arg.begins_with("+") and arg.ends_with("d") and arg.substr(1, arg.length() - 2).is_valid_int():
		var days: int = int(arg.substr(1, arg.length() - 2))
		Clock.advance_minutes(days * 60 * 24)
		return "Advanced %dd → %s" % [days, Clock.format_clock()]
	var hour: int = 0
	var minute: int = 0
	if ":" in arg:
		var bits: PackedStringArray = arg.split(":")
		if bits.size() != 2 or not String(bits[0]).is_valid_int() or not String(bits[1]).is_valid_int():
			return "Usage: time [+1h|+1d|HH|HH:MM]"
		hour = int(bits[0])
		minute = int(bits[1])
	elif arg.is_valid_int():
		hour = int(arg)
	else:
		return "Usage: time [+1h|+1d|HH|HH:MM]"
	if hour < 0 or hour > 23 or minute < 0 or minute > 59:
		return "Hour must be 0–23 and minute 0–59."
	Clock.apply_snapshot({
		"year": Clock.year,
		"month": Clock.month,
		"day": Clock.day,
		"hour": hour,
		"minute": minute,
		"second": 0,
	})
	return "Time set → %s" % Clock.format_clock()


func _cmd_event(args: PackedStringArray) -> String:
	var events: EventCalendar = Game.events
	var sub: String = "list" if args.is_empty() else String(args[0]).to_lower()
	if sub == "list":
		return "\n".join(events.describe())
	if sub == "stop" and args.size() < 2:
		events.clear_forced()
		_sync_events()
		return "Cleared all forced events."
	if args.size() < 2:
		return "Usage: event [list | start <id> | stop [id] | goto <id> | special <id>]"
	var id: StringName = StringName(String(args[1]).to_lower())
	if not EventSchedule.has_id(id):
		return "Unknown event '%s'. Tab lists ids." % String(id)
	match sub:
		"start":
			events.force(id)
			_sync_events()
			return "Started %s (forced until 'event stop %s')." % [EventSchedule.label(id), String(id)]
		"stop":
			events.unforce(id)
			_sync_events()
			if events.is_active(id):
				return "%s is still on the schedule; 'event goto' another date to leave it." % EventSchedule.label(id)
			return "Stopped %s." % EventSchedule.label(id)
		"goto":
			var target: Dictionary = events.next_start(id, EventCalendar.date_from_clock())
			if target.is_empty():
				return "%s has no upcoming start in the calendar. Try 'event start %s'." % [
					EventSchedule.label(id), String(id)
				]
			Clock.set_datetime(
				int(target["year"]), int(target["month"]), int(target["day"]), int(target["hour"])
			)
			return "%s begins → %s" % [EventSchedule.label(id), Clock.format_clock()]
		"special":
			if not events.schedule_special(id, EventCalendar.date_from_clock()):
				return "'%s' is not a special visit. Use: %s" % [
					String(id), ", ".join(PackedStringArray(EventCalendar.SPECIAL_POOL))
				]
			_sync_events()
			return "%s visits now." % EventSchedule.label(id)
	return "Usage: event [list | start <id> | stop [id] | goto <id> | special <id>]"


func _sync_events() -> void:
	Game.events.sync(EventCalendar.date_from_clock())


func _event_ids(sub: String) -> PackedStringArray:
	if sub == "special":
		return PackedStringArray(EventCalendar.SPECIAL_POOL)
	var out: PackedStringArray = []
	for id: StringName in EventSchedule.ids():
		out.append(String(id))
	return out


## Nook's store: level, renovation, hours, raffle and Stalk Market state.
func _cmd_shop(args: PackedStringArray) -> String:
	var shop: ShopBook = Game.shops
	var sub: String = String(args[0]).to_lower() if not args.is_empty() else "status"
	match sub:
		"sales":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "Usage: shop sales <amount>"
			shop.plus_sales(int(args[1]))
		"visitor":
			shop.set_visitor()
		"restock":
			shop.restock(ShopBook.NOOK_ID)
			Game.refresh_shop_set()
		"turnips":
			var week: PackedStringArray = []
			shop.kabu.update(Clock.year, Clock.month, Clock.day)
			for d: int in 7:
				week.append("%s %d" % [String(ClockService.WEEKDAYS[d]).substr(0, 3), shop.kabu.price_on(d)])
			return "Turnips (%s): %s" % [KabuMarket.Trend.keys()[shop.kabu.trend], ", ".join(week)]
		"status":
			pass
		_:
			return "Usage: shop [status | sales <n> | visitor | restock | turnips]"
	return "%s · level %d (earned %d) · sales %d · %s %d:00-%d:00 · renewal day %d · visitor %s" % [
		ShopMail.store_name(shop.nook_level()), shop.nook_level(), shop.real_level(),
		shop.sales_sum(), ShopBook.Status.keys()[shop.nook_status()], shop.nook_open_hour(),
		shop.nook_close_hour(), shop.renewal_day(), "yes" if shop.has_visitor() else "no",
	]


func _cmd_bells(args: PackedStringArray) -> String:
	if args.is_empty():
		return "Bells: %d" % Game.inventory.wallet
	if not String(args[0]).is_valid_int():
		return "Usage: bells <amount>"
	var amount: int = clampi(int(args[0]), 0, Inventory.WALLET_MAX)
	Game.inventory.set_wallet(amount)
	return "Bells set to %d." % Game.inventory.wallet


func _cmd_house(args: PackedStringArray) -> String:
	var house: House = Game.interiors.player_house()
	if house == null:
		return "No player house."
	if args.is_empty():
		return "House: %s (next %s), basement %s, loan %d, order %04d-%02d-%02d%s" % [
			HOUSE_SIZES[mini(int(house.size_tier), HOUSE_SIZES.size() - 1)],
			HOUSE_SIZES[mini(int(house.next_size_tier), HOUSE_SIZES.size() - 1)],
			"yes" if house.has_basement else "no",
			Game.inventory.loan,
			house.order_year,
			house.order_month,
			house.order_day,
			", statue" if HouseUpgrade.is_statue(house) else "",
		]
	match String(args[0]).to_lower():
		"size":
			var idx: int = HOUSE_SIZES.find(String(args[1]).to_lower()) if args.size() >= 2 else -1
			if idx < 0:
				return "Usage: house size <small|medium|large|upper>"
			house.size_tier = idx as House.SizeTier
			house.next_size_tier = idx as House.SizeTier
			if idx < int(House.SizeTier.MEDIUM):
				house.has_basement = false
			Game.interiors.refresh_player_rooms()
			return "House is now %s. Re-enter the world to see the outside." % HOUSE_SIZES[idx]
		"basement":
			house.has_basement = not house.has_basement
			Game.interiors.refresh_player_rooms()
			return "Basement %s." % ("built" if house.has_basement else "removed")
		"build":
			## Make a pending order stale so it lands, as if you had started the game tomorrow.
			var prior: int = house.order_day
			house.order_day = 0 if prior != 0 else 32
			if not Game.check_rehouse_order():
				house.order_day = prior
				return "Nothing is on order."
			return "The order landed. Talk to Tom Nook."
		"loan":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "Usage: house loan <amount>"
			Game.inventory.set_loan(maxi(int(args[1]), 0))
			return "Loan set to %d." % Game.inventory.loan
		"goki":
			if args.size() < 2 or not String(args[1]).is_valid_int():
				return "Cockroaches waiting: %d (last played %d days ago)." % [house.goki_count, HouseGoki.days_away(house)]
			house.goki_count = HouseGoki.clamp_count(int(args[1]))
			return "%d cockroaches are waiting in the walls." % house.goki_count
		"neglect":
			var days: int = int(args[1]) if args.size() >= 2 and String(args[1]).is_valid_int() else 10
			var then: Dictionary = Time.get_datetime_dict_from_unix_time(
				int(Time.get_unix_time_from_datetime_dict({"year": Clock.year, "month": Clock.month, "day": Clock.day, "hour": 12})) - days * 86400
			)
			house.goki_year = int(then["year"])
			house.goki_month = int(then["month"])
			house.goki_day = int(then["day"])
			HouseGoki.decide_family_count(house)
			return "Away %d days: %d cockroaches waiting." % [days, house.goki_count]
		"statue":
			if args.size() >= 2 and String(args[1]).to_lower() == "built":
				house.next_size_tier = House.SizeTier.STATUE
				house.statue_rank = clampi(int(args[2]), 0, 3) if args.size() >= 3 else 0
				var tree := Engine.get_main_loop() as SceneTree
				if tree != null:
					for node: Node in tree.get_nodes_in_group(Statue.GROUP):
						(node as Statue).refresh()
				return "The statue stands by the station (rank %d)." % house.statue_rank
			house.size_tier = House.SizeTier.UPPER
			house.next_size_tier = House.SizeTier.UPPER
			Game.inventory.set_loan(0)
			return "House is at its final size with no loan. Talk to Tom Nook about the statue."
		"roof":
			house.outlook_pal = clampi(int(args[1]), 0, PlayerHouse.ROOF_LETTERS.length() - 1) if args.size() >= 2 else 0
			house.next_outlook_pal = house.outlook_pal
			house.ordered_outlook_pal = house.outlook_pal
			var roof_tree := Engine.get_main_loop() as SceneTree
			if roof_tree != null:
				var plot: Node = roof_tree.root.find_child(String(PlayerHouse.owned_building_id()), true, false)
				if plot != null and plot.has_method("refresh_seasonal_visual"):
					plot.call("refresh_seasonal_visual")
			return "Roof colour %d." % house.outlook_pal
		_:
			return "Usage: house [size|basement|build|loan|statue|roof N]"


func _item_label(data: ItemData) -> String:
	if data.display_name.strip_edges() != "":
		return data.display_name
	return String(data.id)


func _parse_intensity(name: String) -> int:
	match name.to_lower():
		"none", "0":
			return int(Weather.Intensity.NONE)
		"light", "1":
			return int(Weather.Intensity.LIGHT)
		"normal", "2":
			return int(Weather.Intensity.NORMAL)
		"heavy", "3":
			return int(Weather.Intensity.HEAVY)
		_:
			return -1


func _parse_season(name: String) -> int:
	match name:
		"spring":
			return int(ClockService.Season.SPRING)
		"summer":
			return int(ClockService.Season.SUMMER)
		"autumn", "fall":
			return int(ClockService.Season.AUTUMN)
		"winter":
			return int(ClockService.Season.WINTER)
		_:
			return -1


func _item_ids() -> PackedStringArray:
	ItemCatalog.ensure_loaded()
	var ids: Array[String] = []
	for item: ItemData in ItemCatalog.all_items():
		if item != null and item.id != &"":
			ids.append(String(item.id))
	ids.sort()
	return PackedStringArray(ids)


func _filter_prefix(options: PackedStringArray, token: String) -> PackedStringArray:
	var needle: String = token.to_lower()
	var out: PackedStringArray = []
	for opt: String in options:
		if needle.is_empty() or String(opt).to_lower().begins_with(needle):
			out.append(opt)
	return out


func _token_at_end(line: String) -> Dictionary:
	## Strip a leading `/` for command matching but keep spacing for rewrite.
	var working: String = line
	var slash: bool = working.begins_with("/")
	if slash:
		working = working.substr(1)
	var parts: PackedStringArray = working.split(" ", false)
	var ends_space: bool = line.ends_with(" ")
	if working.strip_edges().is_empty():
		return {"token": "", "index": 0, "prior": PackedStringArray(), "prefix": "/" if slash else ""}
	if ends_space:
		return {
			"token": "",
			"index": parts.size(),
			"prior": parts,
			"prefix": line,
		}
	var token: String = String(parts[parts.size() - 1])
	var prior: PackedStringArray = parts.slice(0, parts.size() - 1)
	var prefix: String = line.substr(0, line.length() - token.length())
	return {"token": token, "index": prior.size(), "prior": prior, "prefix": prefix}


func _common_prefix(values: PackedStringArray) -> String:
	if values.is_empty():
		return ""
	var prefix: String = String(values[0])
	for i: int in range(1, values.size()):
		var s: String = String(values[i])
		var n: int = mini(prefix.length(), s.length())
		var j: int = 0
		while j < n and prefix[j].to_lower() == s[j].to_lower():
			j += 1
		prefix = prefix.substr(0, j)
		if prefix.is_empty():
			return ""
	return prefix
