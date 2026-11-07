class_name MenuOverlay
extends CanvasLayer

## A menu window (pockets, map, letters, settings …): whether it is up, the rect it fills on
## screen (a tap outside it closes it, `WindowDismiss`) and how it closes.


func is_open() -> bool:
	return false


func menu_rect() -> Rect2:
	return Rect2()


func dismiss() -> void:
	pass
