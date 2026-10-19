extends RefCounted
## Loading and feedback must both finish before the single scene handoff.
var minimum_transition := 1.05
var modal_open := false
var busy := false
var committed := false
var elapsed := 0.0

func begin() -> bool:
	if busy or modal_open: return false
	busy = true
	committed = false
	elapsed = 0.0
	return true

func advance(delta: float, loaded: bool, failed: bool) -> StringName:
	if not busy or committed: return &"wait"
	if failed:
		recover()
		return &"failed"
	if is_finite(delta): elapsed += maxf(delta, 0.0)
	if loaded and elapsed >= minimum_transition:
		committed = true
		return &"commit"
	return &"wait"

func recover() -> void:
	busy = false
	committed = false
	elapsed = 0.0
