extends WaveEnemy
var ticks := 0
var stunned_ticks := 0
var during_tick: Callable
func supports_central_update() -> bool: return true
func _combat_tick(_delta: float) -> void:
	ticks += 1
	if during_tick.is_valid(): during_tick.call()
func _stunned_tick(_delta: float) -> void: stunned_ticks += 1
