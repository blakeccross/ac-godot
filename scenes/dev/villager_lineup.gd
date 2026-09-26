extends Node3D

## Villagers side by side for texture checks — every `npc_draw_data` texture set on its
## species GLB. `tools/capture.sh scene=res://scenes/dev/villager_lineup.tscn ids=stu,angus`
## (default: every bull); `cam=x,y,z look=x,y,z` override the framing, `anim=npc_1_walk1
## at=0.4` poses every villager on that clip at that time (seconds). Layout, lights and
## camera live in the .tscn; this only fills `Lineup` with the requested villagers.

const SPACING := 1.6

@onready var _lineup: Node3D = $Lineup
@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	var ids: PackedStringArray = PackedStringArray()
	var cam := Vector3.INF
	var look := Vector3(0.0, 0.7, 0.0)
	var anim := ""
	var at := 0.0
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("ids="):
			ids = arg.substr(4).split(",", false)
		elif arg.begins_with("cam="):
			cam = _vec3(arg.substr(4))
		elif arg.begins_with("look="):
			look = _vec3(arg.substr(5))
		elif arg.begins_with("anim="):
			anim = arg.substr(5)
		elif arg.begins_with("at="):
			at = float(arg.substr(3))
	var roster: Array[VillagerData] = []
	for id: String in ids:
		var data := VillagerCatalog.get_villager(StringName(id))
		if data != null:
			roster.append(data)
	if roster.is_empty():
		for data: VillagerData in VillagerCatalog.all_villagers():
			if data.species == &"bull":
				roster.append(data)
	for i: int in roster.size():
		var slot := Node3D.new()
		slot.name = String(roster[i].id)
		_lineup.add_child(slot)
		slot.position = Vector3((i - (roster.size() - 1) * 0.5) * SPACING, 0.0, 0.0)
		var vis := GeneratedVisual.attach_villager(slot, roster[i].species)
		VillagerTextures.apply(vis, roster[i].texture_set)
		NpcFace.new().bind(vis, roster[i].species, roster[i].texture_set)
		print("LINEUP ", roster[i].id, " ", roster[i].texture_set)
		var player := VisualAnimation.find_animation_player(vis)
		if player != null and not anim.is_empty():
			for clip: StringName in player.get_animation_list():
				if String(clip).ends_with(anim):
					player.play(clip)
					player.seek(at, true)
					player.pause()
					break
	_camera.position = cam if cam != Vector3.INF else Vector3(0.0, 1.4, 2.0 + roster.size() * 0.95)
	_camera.look_at(look)


func _vec3(text: String) -> Vector3:
	var p := text.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2])) if p.size() == 3 else Vector3.ZERO
