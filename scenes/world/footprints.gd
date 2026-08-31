extends MultiMeshInstance3D

## Footprint pool for the acre. One MultiMesh, one draw call, ring buffer of prints —
## the original spawns a real effect per foot and lets each expire, but 160 frames of
## life at a run cadence never needs more than a few dozen quads alive.
##
## Rules and geometry live in `FootprintMarks`. This node only writes instance
## transforms and advances the shader clock.

const SHADER := preload("res://shaders/footprint.gdshader")
const POOL_SIZE := 96

var _material: ShaderMaterial
var _next: int = 0
var _now: float = 0.0


func _ready() -> void:
	add_to_group("footprints")
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = FootprintMarks.MARK_SIZE
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	## Above the ocean/river sheets (priority 1) and the mouth splash (2). Without this the
	## transparent queue sorts prints before the shore water and the water paints over them,
	## which erases every mark on wet sand no matter where it sits in world space. The
	## original draws footprints into the XLU effect pass, after the field's own XLU water.
	_material.render_priority = 3
	_material.set_shader_parameter("life_seconds", FootprintMarks.LIFETIME)
	_material.set_shader_parameter(
		"fade_start_seconds", FootprintMarks.FADE_START_FRAME / FootprintMarks.GAME_FPS
	)
	_material.set_shader_parameter(
		"fade_end_seconds", FootprintMarks.FADE_END_FRAME / FootprintMarks.GAME_FPS
	)
	_material.set_shader_parameter("max_alpha", FootprintMarks.MAX_ALPHA)
	_material.set_shader_parameter(
		"aspect", FootprintMarks.MARK_SIZE.x / FootprintMarks.MARK_SIZE.y
	)
	_material.set_shader_parameter("rim_radii", FootprintMarks.rim_radii_uv())
	_material.set_shader_parameter("rim_reach", FootprintMarks.rim_reach_uv())
	_material.set_shader_parameter("tile_peak", FootprintMarks.TILE_PEAK)
	_material.set_shader_parameter("interior_alpha", FootprintMarks.INTERIOR_ALPHA)
	_material.set_shader_parameter("sand_tint", FootprintMarks.SAND_TINT)
	_material.set_shader_parameter("snow_tint", FootprintMarks.SNOW_TINT)
	plane.material = _material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = POOL_SIZE
	mm.visible_instance_count = POOL_SIZE
	mm.mesh = plane
	multimesh = mm
	## Unspawned instances would otherwise draw at the identity transform until first use.
	## A negative spawn time puts their age past `life_seconds`, which the shader discards.
	for i: int in POOL_SIZE:
		mm.set_instance_custom_data(i, Color(-FootprintMarks.LIFETIME * 2.0, 0.0, 0.0, 0.0))
	_material.set_shader_parameter("now", _now)


func _process(delta: float) -> void:
	_now += delta
	_material.set_shader_parameter("now", _now)


func spawn(xform: Transform3D, snow: bool) -> void:
	if multimesh == null or xform.basis.determinant() == 0.0:
		return
	multimesh.set_instance_transform(_next, xform)
	multimesh.set_instance_custom_data(_next, Color(_now, 1.0 if snow else 0.0, 0.0, 0.0))
	_next = (_next + 1) % POOL_SIZE
