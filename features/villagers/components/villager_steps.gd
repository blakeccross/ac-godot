class_name VillagerSteps
extends RefCounted

## What a villager's animations make as they play (`aNPC_anime_se_proc`, `aNPC_anime_proc_foot`).
## Each animation lists the keyframes its feet land on and the sounds it makes (`data/npc/
## npc_steps.json`, from `tools/gen_npc_steps.py`). A foot plant sounds the ground underfoot
## (`aNPC_WalkSe` → `sAdo_Get_WalkLabel`), scuffs a bush, and leaves a print in snow or sand
## (`WALK_ASIMOTO`, `FOOTPRINT`) — nothing of it for a villager who is out of sight.

const DATA_PATH := "res://data/npc/npc_steps.json"
const STEP_L := &"step_l"
const STEP_R := &"step_r"
const SOUND_PREFIX := "se_"

static var _table: Dictionary = {}


static func table() -> Dictionary:
	if _table.is_empty() and FileAccess.file_exists(DATA_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_table = parsed
	return _table


## `{clip: [[seconds-as-frames, event], …]}` for `BodyAnimator.add_clip_events`; `resolve` maps a
## decomp clip name to the model's own (`Villager._resolve_clip`). A tumble's thud is not here:
## it has its own label (`sAdo_Get_KokeruLabel`).
static func marks(resolve: Callable) -> Dictionary:
	var out: Dictionary = {}
	var data: Dictionary = table()
	for name: String in data:
		var clip: String = str(resolve.call(name))
		if clip.is_empty():
			continue
		var entry: Dictionary = data[name]
		var list: Array = []
		## Keyframes count from 1; the clip's time from 0.
		if not name.contains("kokeru"):
			for frame: Variant in entry.get("l", []):
				list.append([float(frame) - 1.0, STEP_L])
			for frame: Variant in entry.get("r", []):
				list.append([float(frame) - 1.0, STEP_R])
		for other: Variant in entry.get("other", []):
			for frame: Variant in (other as Dictionary).get("frames", []):
				list.append([float(frame) - 1.0, StringName(SOUND_PREFIX + "%x" % int((other as Dictionary)["se"]))])
		if not list.is_empty():
			out[StringName(clip)] = list
	return out


## The animation-specific sound named by `event`, or `&""` for a foot event.
static func sound_of(event: StringName) -> StringName:
	var text: String = String(event)
	return StringName(text.substr(SOUND_PREFIX.length())) if text.begins_with(SOUND_PREFIX) else &""


## A foot of `villager` lands: the sound and, outdoors, the scuff and the print.
static func plant(villager: Node3D, visual: Node, right: bool, running: bool, bg: Array) -> void:
	if villager == null or not villager.is_visible_in_tree():
		return
	var gait: PlayerLocomotion.Gait = PlayerLocomotion.Gait.RUN if running else PlayerLocomotion.Gait.WALK
	var season: Clock.Season = Clock.season()
	var indoors: bool = bg.size() != 2 or Game.is_indoors()
	if indoors:
		var floor_index: int = -1
		if Game.interior_session != null and Game.interior_session.room != null:
			floor_index = InteriorStyleCatalog.style_index(Game.interior_session.room.floor_id, "floor_")
		FootstepSe.play_at(villager, -1, WorldGrid.Terrain.GRASS, season, gait, true, floor_index)
		return
	var data := bg[0] as WorldData
	var grid := bg[1] as WorldGrid
	var attr: int = FieldCollision.unit_attr_at(data, grid, villager.global_position)
	var terrain: WorldGrid.Terrain = data.terrain_at(grid.world_to_cell(villager.global_position))
	FootstepSe.play_at(villager, attr, terrain, season, gait, false)
	var anchor: Transform3D = foot_anchor(visual, right)
	var foot: Vector3 = anchor.origin if anchor.basis.determinant() != 0.0 else villager.global_position
	var yaw: float = anchor.basis.get_euler().y if anchor.basis.determinant() != 0.0 else villager.global_rotation.y
	FootstepEffects.walk_step(bg, foot, yaw, attr)
	var marks: Footprints = Footprints.find(villager.get_tree())
	if marks == null:
		return
	var snow: bool
	if attr >= 0:
		if not FootprintMarks.marks_attr(attr, season):
			return
		snow = FootprintMarks.is_snow_mark(attr)
	else:
		if not FootprintMarks.marks_terrain(terrain, season):
			return
		snow = terrain != WorldGrid.Terrain.SAND
	var xform: Transform3D = FootprintMarks.mark_transform(data, grid, foot, yaw)
	if xform.basis.determinant() != 0.0:
		marks.spawn(xform, snow)


## The foot joint's world transform (`Matrix_Position_Zero` on `RFOOT3` / `LFOOT3`); a zero basis
## when the model has no such joint.
static func foot_anchor(visual: Node, right: bool) -> Transform3D:
	var skeleton: Skeleton3D = HeldTool.find_skeleton(visual)
	if skeleton == null:
		return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	var want: String = "rfoot3" if right else "lfoot3"
	for i: int in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).to_lower().begins_with(want):
			return skeleton.global_transform * skeleton.get_bone_global_pose(i)
	return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
