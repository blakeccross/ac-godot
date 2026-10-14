class_name PhysicsLayers
extends RefCounted

## Bits of the named 3D physics layers in `project.godot` (`layer_names/3d_physics`). Scenes
## set their layers in the `.tscn`; code that queries or toggles a layer names it here.

const WORLD := 1 << 0
const PLAYER := 1 << 1
const ACTORS := 1 << 2
const INTERACT := 1 << 3
## Catch spheres of bugs and fish (`Bug.CatchArea`).
const CREATURES := 1 << 4
const PICKUPS := 1 << 5
const WATER := 1 << 6
const TRIGGERS := 1 << 7
