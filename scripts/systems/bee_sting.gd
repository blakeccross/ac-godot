class_name BeeSting
extends RefCounted

## Bees and what they leave behind: a swarm after the player, then a swollen face that lasts
## until the game is reset. Never saved (`Common` data).

## The player's face texture changed (`mPlib_change_player_face`).
signal face_changed

## `player_bee_chase_flag`: a swarm is out after the player (villagers cry "Bees!").
var chasing: bool = false
## `player_bee_swell_flag`: stung, so the face is swollen.
var swollen: bool = false
## `npclist[].conversation_flags.beesting`, inverted: villagers who have greeted the player
## since the sting and so no longer remark on the face.
var _greeted: Dictionary = {}


func clear() -> void:
	chasing = false
	swollen = false
	_greeted.clear()


## `Stung_bee` frame 21 of `HATI2`: the face swells and, on the first sting only, every
## villager gets a remark ready (`mNpc_SetTalkBee`).
func sting() -> void:
	chasing = false
	if swollen:
		return
	swollen = true
	_greeted.clear()
	face_changed.emit()


## Set the swelling directly, for the debug console.
func set_swollen(value: bool) -> void:
	swollen = value
	_greeted.clear()
	face_changed.emit()


## Whether `villager_id` still has the swollen-face remark to make.
func remark_pending(villager_id: StringName) -> bool:
	return swollen and villager_id != &"" and not _greeted.has(villager_id)


## Any greeting spends the remark (`conversation_flags.beesting = FALSE`).
func note_greeting(villager_id: StringName) -> void:
	if swollen and villager_id != &"":
		_greeted[villager_id] = true
