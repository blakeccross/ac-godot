class_name TestTalkActions
extends GdUnitTestSuite

## `TalkActions` plays a `TalkStep`'s demo and answers the runner: what the pockets gave reaches
## the talk script, and a hand-over with nobody there to act it out still lets the talk go on.


class PocketsTalk:
	extends BankTalk

	var first: TalkStep
	var handed: Array = []

	func next_step() -> TalkStep:
		var step := first
		first = null
		return step

	func hand_result(item: StringName, pocket: int = -1) -> TalkStep:
		handed = [item, pocket]
		return null


func after_test() -> void:
	Game.pocket_requests.cancel_handover()


## An authored one-node talk that ends at once, so the runner asks `next_step` for its step.
func _start(talk: PocketsTalk) -> DialogueOverlay:
	var overlay: DialogueOverlay = auto_free(load("res://scenes/ui/dialogue_overlay.tscn").instantiate())
	add_child(overlay)
	var runner := DialogueRunner.new()
	overlay._runner = runner
	runner.talk_manager = talk
	runner.action_requested.connect(func(step: TalkStep) -> void: TalkActions.handle(step, overlay, null, null))
	var data := DialogueData.from_dict({"id": "fx", "start": "a", "nodes": {"a": {"type": "event", "events": []}}})
	runner.start(data, DialogueContext.new())
	return overlay


func test_the_pockets_pick_reaches_the_talk_script() -> void:
	var talk := PocketsTalk.new()
	talk.first = TalkStep.open_pockets("take")
	var overlay := _start(talk)
	assert_bool(overlay.is_suspended()).is_true()
	assert_bool(Game.pocket_requests.handover_pending).is_true()
	Game.pocket_requests.handover_resolved.emit(&"apple", 3)
	assert_array(talk.handed).contains_exactly([&"apple", 3])
	assert_bool(overlay.is_suspended()).is_false()
	assert_bool(overlay.runner().done).is_true()


## No pockets screen to open: the request cancels on the next frame, after the step is waiting.
func test_no_pockets_screen_hands_over_nothing() -> void:
	var talk := PocketsTalk.new()
	talk.first = TalkStep.open_pockets("take")
	var overlay := _start(talk)
	await get_tree().process_frame
	assert_array(talk.handed).contains_exactly([&"", -1])
	assert_bool(overlay.runner().done).is_true()


## Nobody to act out the hand-over: it is skipped and the step chained after it runs.
func test_a_hand_over_without_actors_runs_on_to_the_next_step() -> void:
	var talk := PocketsTalk.new()
	talk.first = TalkStep.give(&"apple").then_step(TalkStep.open_pockets("take"))
	var overlay := _start(talk)
	assert_bool(overlay.runner().waiting_action).is_true()
	assert_bool(Game.pocket_requests.handover_pending).is_true()
	Game.pocket_requests.handover_resolved.emit(&"pear", 0)
	assert_array(talk.handed).contains_exactly([&"pear", 0])
