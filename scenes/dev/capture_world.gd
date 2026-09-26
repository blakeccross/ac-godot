extends Node3D

## One-shot render capture for visual checks (the unit suite is headless and cannot see
## pixels — see docs/testing.md). Boots a generated town (or any scene), frames a target
## and writes PNGs. Driven by user args; `tools/capture.sh` wraps it and filters noise.
##
##   tools/capture.sh target=visual:TREE_APPLE_FRUIT date=2001-01-15,2001-04-05
##   tools/capture.sh target=node:Buildings/station cam=-6,5,9
##   tools/capture.sh target=acre:acre_5_6 cam=0,8,9 look=0,0,-1.5
##   tools/capture.sh scene=res://scenes/ui/intro_train.tscn wait=240
##
## Args (all optional):
##   scene=res://…     Scene to instance instead of the generated town.
##   seed=12345        Generated-town seed.
##   date=Y-M-D[,…]    One capture per date (default 2001-07-15). time=HH:MM (12:00).
##   target=…          visual:<id or glob> | node:<path under world> | acre:<name> |
##                     bug:<id or glob> (a live field insect, e.g. bug:*grasshopper*) |
##                     pos:x,y,z | scene (keep the scene's own camera). Default: scene
##                     camera for scene=, else the town centre.
##   console=cmd,args  Debug-console command run once the scene is up, commas for spaces
##                     (`console=bug,grasshopper,3`).
##   cam=dx,dy,dz      Camera offset from the focus in metres (default 0,4,7).
##   look=dx,dy,dz     Offset added to the focus point (default 0,1,0).
##   fov=50  size=960x540  wait=20 (frames before the grab)
##   out=path          Directory or .png path (default res://.tmp_captures/, gitignored).
##   name=label        File stem (default from target + date).
## Prints one `CAPTURE <absolute path>` line per image, `CAPTURE_ERROR <msg>` on failure.

const WORLD_SCENE := "res://scenes/world/world.tscn"
const DEFAULT_OUT := "res://.tmp_captures"

var _args: Dictionary = {}


func _ready() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	Clock.paused = true
	var size := _vec2i(str(_args.get("size", "960x540")), Vector2i(960, 540))
	get_window().size = size
	get_viewport().size = size
	call_deferred("_run")


func _run() -> void:
	var dates: PackedStringArray = str(_args.get("date", "2001-07-15")).split(",", false)
	for date: String in dates:
		await _capture_date(date.strip_edges())
	get_tree().quit()


func _capture_date(date: String) -> void:
	var ymd := date.split("-")
	if ymd.size() != 3:
		_error("bad date '%s' (want Y-M-D)" % date)
		return
	var hm := str(_args.get("time", "12:00")).split(":")
	Game.reset_session()
	var scene_path := str(_args.get("scene", ""))
	if scene_path.is_empty():
		var seed_value := int(_args.get("seed", "12345"))
		Game.world_mode = WorldData.Mode.GENERATED
		Game.world_seed = seed_value
		Game.grass_pattern = WorldGenerator.decide_grass_pattern(seed_value)
	Clock.apply_snapshot({
		"year": int(ymd[0]), "month": int(ymd[1]), "day": int(ymd[2]),
		"hour": int(hm[0]), "minute": int(hm[1]) if hm.size() > 1 else 0, "second": 0,
	})
	var packed := load(scene_path if not scene_path.is_empty() else WORLD_SCENE) as PackedScene
	if packed == null:
		_error("cannot load scene '%s'" % scene_path)
		return
	var root: Node = packed.instantiate()
	add_child(root)
	for _i: int in 10:
		await get_tree().process_frame
	if _args.has("console"):
		print("CONSOLE ", DebugConsole.new().execute(str(_args["console"]).replace(",", " ")))
	var target := str(_args.get("target", "scene" if not scene_path.is_empty() else "town"))
	var cam: Camera3D = null
	if target != "scene":
		var focus: Variant = _resolve_focus(root, target)
		## Insects spawn over time: keep looking for up to `wait` frames.
		if focus == null and target.begins_with("bug:"):
			for _i: int in int(_args.get("wait", "20")):
				await get_tree().process_frame
				focus = _resolve_focus(root, target)
				if focus != null:
					break
		if focus == null:
			_error("target '%s' not found" % target)
			root.queue_free()
			await get_tree().process_frame
			return
		cam = Camera3D.new()
		cam.fov = float(_args.get("fov", "50"))
		cam.near = 0.05
		add_child(cam)
		cam.current = true
		var look_at: Vector3 = (focus as Vector3) + _vec3(str(_args.get("look", "0,1,0")), Vector3(0, 1, 0))
		cam.global_position = look_at + _vec3(str(_args.get("cam", "0,4,7")), Vector3(0, 4, 7))
		cam.look_at(look_at)
	for _i: int in int(_args.get("wait", "20")):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := _out_path(target, date)
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		_error("save failed (%d) %s" % [err, path])
	else:
		print("CAPTURE ", ProjectSettings.globalize_path(path))
	if cam != null:
		cam.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _resolve_focus(root: Node, target: String) -> Variant:
	var kind := target.get_slice(":", 0)
	var value := target.substr(kind.length() + 1)
	match kind:
		"town":
			var acres := root.get_node_or_null("Terrain/Acres")
			if acres == null:
				return Vector3.ZERO
			var box := AABB()
			var first := true
			for child: Node in acres.get_children():
				if child is Node3D:
					var p: Vector3 = (child as Node3D).global_position
					box = AABB(p, Vector3.ZERO) if first else box.expand(p)
					first = false
			return box.get_center()
		"pos":
			return _vec3(value, Vector3.ZERO)
		"node":
			var node := root.get_node_or_null(value) as Node3D
			return node.global_position if node != null else null
		"acre":
			var acre := root.get_node_or_null("Terrain/Acres/" + value) as Node3D
			if acre == null:
				return null
			return acre.global_position + Vector3(8.0, 0.0, 8.0)
		"visual":
			var hit := _find_visual(root, value)
			return hit.global_position if hit != null else null
		"bug":
			for node: Node in root.find_children("*", "BugActorVisual", true, false):
				var bug := node as BugActorVisual
				if bug.visible and (String(bug.bug_id) == value or String(bug.bug_id).match(value)):
					return bug.global_position
			return null
	return null


func _find_visual(node: Node, pattern: String) -> Node3D:
	if node is Node3D and "visual_id" in node:
		var vid := str(node.get("visual_id"))
		if vid == pattern or vid.match(pattern):
			return node as Node3D
	for child: Node in node.get_children():
		var hit := _find_visual(child, pattern)
		if hit != null:
			return hit
	return null


func _out_path(target: String, date: String) -> String:
	var out := str(_args.get("out", DEFAULT_OUT))
	var many := str(_args.get("date", "")).split(",", false).size() > 1
	if out.ends_with(".png"):
		return out.trim_suffix(".png") + "_" + date + ".png" if many else out
	var stem := str(_args.get("name", ""))
	if stem.is_empty():
		stem = target.replace(":", "_").replace("/", "_").replace("*", "x").replace(",", "_")
		stem += "_" + date
	elif many:
		stem += "_" + date
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	return out.path_join(stem + ".png")


func _error(msg: String) -> void:
	print("CAPTURE_ERROR ", msg)


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for arg: String in raw:
		var eq := arg.find("=")
		if eq > 0:
			out[arg.substr(0, eq)] = arg.substr(eq + 1)
	return out


static func _vec3(text: String, fallback: Vector3) -> Vector3:
	var p := text.split(",")
	if p.size() != 3:
		return fallback
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


static func _vec2i(text: String, fallback: Vector2i) -> Vector2i:
	var p := text.to_lower().split("x")
	if p.size() != 2:
		return fallback
	return Vector2i(int(p[0]), int(p[1]))
