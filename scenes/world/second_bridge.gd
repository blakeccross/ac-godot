extends Node3D

## The second bridge Tortimer builds (`ac_bridge_a`, `BRIDGE_A0` / `BRIDGE_A1`): the wood
## bridge model, winter-white in winter. Its deck is `SecondBridge.apply_collision`.

const VISUAL := &"obj_s_bridgeA"

## 0: `BRIDGE_A0`; 1: `BRIDGE_A1` (turned −90°).
@export var kind: int = 0


func _ready() -> void:
	GeneratedVisual.attach(self, VISUAL)


func refresh_seasonal_visual() -> void:
	GeneratedVisual.refresh(self, VISUAL)
