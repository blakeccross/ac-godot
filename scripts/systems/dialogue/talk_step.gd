class_name TalkStep
extends RefCounted

## One move of a `BankTalk` script, played by `DialogueRunner`. Demos run first, in this
## order, then the message:
##
## - `pockets_mode` set: the pockets open for the player to pick (`BankTalk.hand_result`).
## - `text_len` > 0: the letter board opens for one line (`BankTalk.text_result`).
## - `handover` set: `item` changes hands (`HandOver`); `after` runs once it has.
## - `msg` ≥ 0: that message, with `choices` as a menu once it ends.
##
## A `BankTalk` method returns null for "nothing" (end the talk, or no demo).

enum Handover { NONE, NPC_GIVES, PLAYER_GIVES }

var msg: int = -1
var choices: Array[String] = []
var handover: Handover = Handover.NONE
var item: StringName = &""
## `Game.pocket_requests.request_handover` mode ("quest", "take", "shrine"); empty for none.
var pockets_mode: String = ""
var pocket: int = -1
## `mSM_OVL_LEDIT`: line length, lines and starting text.
var text_len: int = 0
var text_lines: int = 1
var text_initial: String = ""
## Another step once this one's hand-over has played.
var after: TalkStep


static func show(msg_no: int, menu: Array[String] = []) -> TalkStep:
	var step := TalkStep.new()
	step.msg = msg_no
	step.choices = menu.duplicate()
	return step


## The NPC hands `id` to the player.
static func give(id: StringName) -> TalkStep:
	return _pass(Handover.NPC_GIVES, id)


## The player hands `id` to the NPC.
static func take(id: StringName) -> TalkStep:
	return _pass(Handover.PLAYER_GIVES, id)


static func open_pockets(mode: String, slot: int = -1) -> TalkStep:
	var step := TalkStep.new()
	step.pockets_mode = mode
	step.pocket = slot
	return step


static func edit_text(length: int, lines: int = 1, initial: String = "") -> TalkStep:
	var step := TalkStep.new()
	step.text_len = length
	step.text_lines = lines
	step.text_initial = initial
	return step


static func _pass(kind: Handover, id: StringName) -> TalkStep:
	var step := TalkStep.new()
	step.handover = kind
	step.item = id
	return step


## Show `msg_no` after this step's demo.
func then_show(msg_no: int, menu: Array[String] = []) -> TalkStep:
	msg = msg_no
	choices = menu.duplicate()
	return self


## Run `next` after this step's hand-over.
func then_step(next: TalkStep) -> TalkStep:
	after = next
	return self


func has_handover() -> bool:
	return handover != Handover.NONE and item != &""


## A demo the world plays before the runner goes on (pockets, letter board, hand-over).
func needs_action() -> bool:
	return pockets_mode != "" or text_len > 0 or has_handover()


## The same step without its hand-over: what is left once it has played.
func without_handover() -> TalkStep:
	var rest := TalkStep.show(msg, choices)
	rest.after = after
	return rest
