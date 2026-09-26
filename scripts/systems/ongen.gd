class_name Ongen
extends RefCounted

## Positional "sound source" math shared by every `Na_OngenPos` / `Na_OngenTrgStart` caller
## (train, insects): distance and pan are measured from `Camera2_getMicPos`, the player
## lifted `MIC_OFFSET_GX`, never from the render camera.

## `Camera2_getMicPos`: player + (0, 240, 77) GX.
const MIC_OFFSET_GX := Vector3(0.0, 240.0, 77.0)
## `SOU_ONGEN_AREA1`: beyond this a level source is dropped and a trigger never starts.
const AREA := 540.0
const BASE_VOLUME := 1.15


## `distance2vol`: 1.15 at the mic, 0 at `AREA`.
static func volume(distance: float) -> float:
	if distance > AREA:
		return 0.0
	return minf(BASE_VOLUME - (BASE_VOLUME / (AREA * AREA)) * distance * distance, 1.5)


## `atans_table(dz, dx)` → `angle2pan` (without the `pan_kochou` curve): −1 left … 1 right.
## Due east is hard right, due west hard left, north / south centred.
static func pan(mic: Vector3, source: Vector3) -> float:
	var angle: int = MLib.rad_to_s16(atan2(source.x - mic.x, source.z - mic.z))
	var a: int = angle >> 8
	var p: int
	if a >= 0x40 and a <= 0xC0:
		p = mini(0x80 - (a - 0x40), 0x7F)
	elif a >= 0xC1:
		p = a - 0xC0
	else:
		p = a + 0x40
	return clampf((float(p) - 64.0) / 64.0, -1.0, 1.0)


## The field mic in GX, or `Vector3.INF` without a player.
static func field_mic_gx(tree: SceneTree) -> Vector3:
	var player := Player.find(tree)
	if player == null:
		return Vector3.INF
	return TownSpace.world_to_gx(player.global_position) + MIC_OFFSET_GX


## A looping copy of a level-SE stream (`lev_*` renders are seamless loops).
static func looped(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var copy: AudioStream = stream.duplicate()
	if copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	elif copy is AudioStreamWAV:
		(copy as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return copy
