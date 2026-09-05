extends MeshInstance3D

## Draws a soft elliptical blob under its parent (player, villager, …). Snaps to the
## outdoor heightfield when a `world` group host is present; otherwise rides parent Y.

const SHADER := preload("res://shaders/actor_blob_shadow.gdshader")

@export var extent: Vector2 = ActorBlobShadow.PLAYER_EXTENT
@export var base_alpha: float = ActorBlobShadow.PLAYER_ALPHA

var _material: ShaderMaterial


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = extent
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	## Above acre water / beach wet (priority 1–2); below footprints (3).
	_material.render_priority = 2
	_material.set_shader_parameter("alpha", base_alpha)
	plane.material = _material
	mesh = plane
	_place()


func _process(_delta: float) -> void:
	_place()


func _place() -> void:
	var host: Node3D = get_parent() as Node3D
	if host == null:
		return
	var yaw: float = host.rotation.y
	if host.has_node("MeshPivot"):
		yaw = (host.get_node("MeshPivot") as Node3D).rotation.y
	var xform: Transform3D
	var bg: Array = _bg()
	if bg.size() == 2:
		xform = ActorBlobShadow.ground_transform(
			bg[0] as WorldData, bg[1] as WorldGrid, host.global_position, yaw
		)
	else:
		xform = ActorBlobShadow.flat_transform(host.global_position, yaw)
	if xform.basis.determinant() == 0.0:
		visible = false
		return
	visible = true
	global_transform = xform
	if _material != null:
		_material.set_shader_parameter("alpha", ActorBlobShadow.precip_alpha(base_alpha))


func _bg() -> Array:
	if get_tree() == null:
		return []
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return []
	var data: Variant = world.get("layout")
	var grid: Variant = world.get("grid")
	if not (data is WorldData) or not (grid is WorldGrid):
		return []
	return [data, grid]
