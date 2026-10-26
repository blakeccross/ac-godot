extends Node3D

## The wasp nest a shaken tree drops (`bIT_actor_drop_wait_bee`). It is not an item: it
## falls, lies on the ground for 120 ticks, then fades out at 5/255 a tick and is gone.

signal landed

const LIE_SECONDS := 120.0 * DecompTime.TICK_SEC
const FADE_SECONDS := (255.0 / 5.0) * DecompTime.TICK_SEC
func _ready() -> void:
	var visual := StringName("obj_%s_honeycomb" % FieldCatalog.season_letter())
	if GeneratedVisual.attach(self, visual) == null:
		GeneratedVisual.attach(self, &"obj_s_honeycomb")


## Drop from `from` onto `to` over `duration` seconds, then lie and fade.
func drop(from: Vector3, to: Vector3, duration: float) -> void:
	global_position = from
	var tween := create_tween()
	tween.tween_property(self, "global_position", to, maxf(duration, 0.0)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(landed.emit)
	tween.tween_interval(LIE_SECONDS)
	tween.tween_method(_set_fade, 0.0, 1.0, FADE_SECONDS)
	tween.tween_callback(queue_free)


func _set_fade(amount: float) -> void:
	for node: Node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).transparency = amount
