class_name SnowmanBreak
extends Node3D

## `eYukidaruma` (`ef_yukidaruma`): a snowman ball bursting. Three models of the ball flying
## apart play six ticks each (the first two ticks of a new one also leave the last as a faint
## ghost), over twenty ticks, and snow clumps (`ef_yukidama`) scatter from it: three, or eight
## from a big ball. Scale grows from 0.01 to 0.03 with the ball's size. A snowman breaks as two
## of them, body and head (`aPSMAN_MakeBreakEffect`).

const MODELS: Array[StringName] = [&"ef_daruma01_00", &"ef_daruma01_01", &"ef_daruma01_02"]
const LIFE_TICKS := 20.0
const BIG := 66
const GX := FieldCatalog.GX_TO_METERS
const CLUMP_SPREAD := 20.0
## `eYukidaruma_dw` `PrimColor` alpha of the ghost of the last model.
const GHOST_ALPHA := 120.0 / 255.0

var percent: int = 50
var _age: float = 0.0
var _meshes: Array[Node3D] = []


## Burst a ball of `percent` (its size × 100) with its base at `pos`, under `host`.
static func spawn(host: Node, pos: Vector3, p_percent: int) -> SnowmanBreak:
	if host == null:
		return null
	var node := SnowmanBreak.new()
	node.percent = p_percent
	node.name = "SnowmanBreak"
	host.add_child(node)
	node.global_position = pos
	node._scatter(host)
	return node


## The model showing at `tick` and the ghost of the one before it (−1 for none). Models are
## `frame / 3` with `frame = tick / 2`; past the third nothing is left but the clumps.
static func models_at(tick: int) -> Vector2i:
	var frame: int = tick >> 1
	@warning_ignore("integer_division")
	var model: int = frame / 3
	var shown: int = model if model < MODELS.size() else -1
	var ghost: int = model - 1 if (frame == 3 or frame == 6 or frame == 9) else -1
	return Vector2i(shown, ghost)


## `calc_adjust(arg0, 0, 100, 0.01, 0.03)`.
static func scale_for(p_percent: int) -> float:
	return lerpf(0.01, 0.03, clampf(float(p_percent) / 100.0, 0.0, 1.0))


static func clump_count(p_percent: int) -> int:
	return 8 if p_percent > BIG else 3


func _ready() -> void:
	for model: StringName in MODELS:
		var paths: PackedStringArray = FieldCatalog.mesh_paths(model)
		var packed: PackedScene = load(paths[0]) as PackedScene if not paths.is_empty() else null
		var holder := Node3D.new()
		if packed != null:
			holder.add_child(packed.instantiate())
		holder.scale = Vector3.ONE * scale_for(percent) * GX / FieldCatalog.PIPELINE_SCALE
		holder.visible = false
		add_child(holder)
		_meshes.append(holder)


func _process(delta: float) -> void:
	_age += delta * DecompTime.TICK_HZ
	if _age >= LIFE_TICKS:
		queue_free()
		return
	var at: Vector2i = models_at(int(_age))
	for i: int in _meshes.size():
		var node: Node3D = _meshes[i]
		node.visible = i == at.x or i == at.y
		var alpha: float = 1.0 if i == at.x else GHOST_ALPHA
		for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).transparency = 1.0 - alpha


## The snow clumps: scattered ±20 GX round the base, each a small clump (`arg1 = 0x4000 | n`).
func _scatter(host: Node) -> void:
	var count: int = clump_count(percent)
	for n: int in range(count - 1, -1, -1):
		var at := global_position + Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)
		) * CLUMP_SPREAD * GX
		FieldEffects.spawn(host, FieldEffects.Kind.YUKIDAMA, at, 0.0, 0, 0x4000 | n)
