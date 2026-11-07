extends EventPresenter

## `snowman_start`: snowman season puts the body ball and the head ball out in town
## (`SnowmanUse.spawn_balls`); they keep their place and size between visits until one is
## broken or built into a snowman.

var _balls: Array[Snowball] = []


func start() -> bool:
	_balls = SnowmanUse.spawn_balls(mgr)
	return true


func stop() -> void:
	## The season is over: the balls go for good (`mEv_clear_common_place`).
	for ball: Snowball in _balls:
		if is_instance_valid(ball):
			ball.discard = true
			ball.queue_free()
	_balls.clear()
	Game.town.snowballs.clear()
