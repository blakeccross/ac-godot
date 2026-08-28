extends Node

## Music / SFX buses. Call play methods from scenes; do not scatter AudioStreamPlayer setup.

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"


func _ready() -> void:
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)


func play_sfx(stream: AudioStream, at: Node = self) -> void:
	if stream == null or at == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = SFX_BUS
	at.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	var index: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
