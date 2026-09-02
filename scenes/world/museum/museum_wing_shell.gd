extends Node3D

## Authored museum acre shell. GLB instances and acre scale live in the tscn;
## this only applies TEX_EDGE materials (same pass as `GeneratedVisual.attach_interior`).


func _ready() -> void:
	var vis: Node3D = get_node_or_null("GeneratedVisual") as Node3D
	if vis == null:
		return
	GeneratedVisual.apply_authored_interior(vis)
