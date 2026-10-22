extends CreatureEnemy

## Integration example only; not registered in any production wave/catalog.
## Attach to a copy of an existing Creature scene with Sprite and Collision.
## Override the behaviour tick, keeping inherited registration, commit, damage,
## freeze, animation, flat movement and feedback-pool lifecycle intact.
func _combat_tick(delta: float) -> void:
	_move_chase(delta, combat_stop_distance)
	_touch_player()

## External movement code must resolve its own action/collision rules, then:
## global_position = destination
## reset_physics_interpolation()
## commit_spatial_state()  # before another attack/neighbor query
