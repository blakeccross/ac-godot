class_name LevelSound
extends AudioStreamPlayer

## A looping "level" SE an actor makes while it is out (`sAdo_OngenPos(actor, level, pos)`):
## a waterfall's rush, the wishing well's hum. Heard from the field mic like any sound
## source (`SoundEmitter`): fading with distance, silent past 540 GX, panned by bearing.

## The catalog's level id (`lev_<hex>`).
@export var level_id: int = 0
## Where the sound sits on its host (the waterfall's is 40 GX, 2 m, up).
@export var offset: Vector3 = Vector3.ZERO

var _host: Node3D


func _ready() -> void:
	_host = get_parent() as Node3D
	stream = SoundEmitter.looped(SeCatalog.stream_for(StringName("lev_%x" % level_id)))
	if stream == null:
		set_process(false)


func _process(_delta: float) -> void:
	if _host == null or not is_inside_tree():
		return
	var at: Vector3 = _host.global_position + offset
	var placed: Vector2 = Audio.field_placement_at(get_tree(), at)
	if placed.x <= 0.0:
		if playing:
			stop()
		return
	volume_db = linear_to_db(placed.x)
	bus = Audio.pan_bus(placed.y)
	if not playing:
		play()
