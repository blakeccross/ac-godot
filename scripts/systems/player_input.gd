class_name PlayerInput
extends RefCounted

## An input source that drives the player instead of the pad and keyboard: the title demo's
## recorded presses (`TitleDemoInput`) and touch (`TouchDriver`). The player reads `move`
## exactly as it would read the stick and takes A / B presses from here, so whatever drives
## it ends in the same verbs — the interaction picked, the walk's physics, the net's hold.

## `Input.get_vector` convention: x right, y toward the camera (forward is negative),
## magnitude 0..1.
var move: Vector2 = Vector2.ZERO
var a_held: bool = false
## Rising edges of A and B, latched until consumed so a press is never lost between ticks.
var a_pressed: bool = false
var b_held: bool = false
var b_pressed: bool = false
## B / L / R held to dash.
var dash_held: bool = false
## The title demo: no dashing, only its own verbs, no bad-luck trips and no checks that
## would make a recording go another way (`TitleDemo.allows_verb`).
var demo: bool = false


## Hold or let go of A; pressing it latches `a_pressed`.
func set_a(held: bool) -> void:
	a_pressed = a_pressed or (held and not a_held)
	a_held = held


func set_b(held: bool) -> void:
	b_pressed = b_pressed or (held and not b_held)
	b_held = held


## A tap: down and up between two ticks.
func tap_a() -> void:
	a_pressed = true


func tap_b() -> void:
	b_pressed = true


## Take the latched A edge; a second reader cannot fire the action twice.
func consume_a_pressed() -> bool:
	var pressed: bool = a_pressed
	a_pressed = false
	return pressed


func consume_b_pressed() -> bool:
	var pressed: bool = b_pressed
	b_pressed = false
	return pressed


func clear() -> void:
	move = Vector2.ZERO
	a_held = false
	a_pressed = false
	b_held = false
	b_pressed = false
	dash_held = false
