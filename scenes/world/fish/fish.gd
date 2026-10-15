class_name Fish
extends Node3D

## A fish in the water as the player sees it: its shadow (`aGYO_actor_draw_gyoei`), or the
## fading puff a scared one leaves (`GYO_KAGE`). `FishSpawner` keeps one per `FishShadow`
## and per `FishSchool.Puff` and places it each frame.

const GROUP := &"field_fish"
## `FishSize.shadow_size` is the original quad; its tiles fill `SILHOUETTE_FILL` of it. The
## shader's SDF body spans `2 * body_radii.y` (0.8) of the node, so the node is scaled up
## until that body is the tiles' silhouette, which also leaves the tail sway its margin.
const SHADER_BODY_SPAN := 0.8
const QUAD_PADDING := FishSize.SILHOUETTE_FILL / SHADER_BODY_SPAN
## `mCoBG_GetWaterHeight` - 8 GX puts the fish under the surface; the quad has to sit just
## above the water plane instead or it z-fights with it. River/ocean sheets also add a
## `ground_lift` of 0.5–1.0 GX in their vertex shader — sit above that or the opaque depth
## write from `depth_draw_opaque` kills the shadow.
const SURFACE_LIFT := 0.1  ## 2 GX

@onready var _shadow: MeshInstance3D = $Shadow


func _ready() -> void:
	add_to_group(GROUP)


## Lays the shadow on the water at `at` (surface height `surface_y`), facing `yaw`, sized
## `extent` (metres), at `alpha`, its tail swung by `blend` (0..1, `aGYO_prim_f`).
func place(at: Vector3, surface_y: float, yaw: float, extent: Vector2, alpha: float, blend: float) -> void:
	visible = alpha > 0.005
	if not visible:
		return
	global_position = Vector3(at.x, surface_y + SURFACE_LIFT, at.z)
	## The quad's +Y runs along the fish and the shadow is laid flat, so yaw stays on Y. The
	## extra half turn is `aGYO_actor_draw_gyoei`'s `rotation.y + DEG2SHORT_ANGLE2(180.0f)`:
	## the shadow art points down its local -Z, so without it the fish swims tail first.
	rotation = Vector3(0.0, yaw + PI, 0.0)
	_shadow.scale = Vector3(extent.x * QUAD_PADDING, extent.y * QUAD_PADDING, 1.0)
	var mat := _shadow.material_override as ShaderMaterial
	if mat == null:
		return
	## `aGYO_prim_f` runs 0..255 as a cross-fade between two tiles. Remapped to -1..1 it is
	## the sway direction, so one table drives the whole wiggle.
	mat.set_shader_parameter("body_flex", blend * 2.0 - 1.0)
	mat.set_shader_parameter("alpha", alpha)
	mat.set_shader_parameter("aspect", FishSize.SHADOW_ASPECT)
