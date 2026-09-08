extends Node3D

## Skylight god-ray mesh for a museum wing (`ac_museum` shine actor). Authored as a node
## at the acre origin; the GLB is attached at runtime so it picks up the light-shaft
## material (unshaded XLU, daylight-scaled alpha). Set `shine_visual` per wing.

@export var shine_visual: StringName = &"obj_museum1_shine"


func _ready() -> void:
	if get_node_or_null("GeneratedVisual") != null:
		return
	if FieldCatalog.mesh_paths(shine_visual).is_empty():
		return
	GeneratedVisual.attach(self, shine_visual)
