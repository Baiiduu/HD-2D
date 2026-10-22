extends "res://scripts/enemies/leaf_charger.gd"

## Only the callback gate is isolated; inherits the actual Creature -> Slime ->
## WaveEnemy chain and real capsule/resource configuration. No timing claim.
var combat_ticks := 0
var tick_time := 0.0
func _combat_tick(delta: float) -> void:
	combat_ticks += 1
	tick_time += delta

## Reference arm adds only the exact removed outer gate.
var legacy_outer_gate := false
func _physics_process(delta: float) -> void:
	if legacy_outer_gate and wave_mode and combat_active.is_valid() and not combat_active.call(): return
	super._physics_process(delta)
