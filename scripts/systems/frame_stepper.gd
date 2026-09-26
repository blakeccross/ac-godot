class_name FrameStepper
extends RefCounted

## Fixed-rate stepper: turns render `delta` into whole decomp ticks so per-frame logic runs
## the same number of times at any render FPS.
##
##     var _steps := FrameStepper.new()
##     _steps.add(delta)
##     while _steps.next():
##         _tick()
##
## Put extra loop conditions *before* `next()` (`while alive and _steps.next()`) so a
## skipped tick stays banked, and cap `backlog` when a hitch shouldn't replay many ticks.

var hz: float
## Most ticks that may be banked at once; `INF` never drops time.
var backlog: float
var _acc: float = 0.0


func _init(rate_hz: float = DecompTime.TICK_HZ, max_backlog: float = INF) -> void:
	hz = rate_hz
	backlog = max_backlog


func add(delta: float) -> void:
	_acc = minf(_acc + maxf(delta, 0.0) * hz, backlog)


## Consumes one banked tick; false when less than a whole tick is left.
func next() -> bool:
	if _acc < 1.0:
		return false
	_acc -= 1.0
	return true


## Adds `delta` and consumes every whole tick at once; returns how many.
func take(delta: float) -> int:
	add(delta)
	var n: int = int(_acc)
	_acc -= float(n)
	return n


## Fraction of a tick banked (0..1 once drained).
func pending() -> float:
	return _acc


func reset() -> void:
	_acc = 0.0
