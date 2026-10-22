extends "res://scripts/player/player_charge_effect.gd"
signal processed
var predictions := 0
var displays := 0
var actual_processes := 0
func display(player: Player, body: PlayerRicochet, visuals: PlayerActionVisuals) -> void:
	displays += 1
	super.display(player, body, visuals)
func _update_aim() -> void:
	predictions += 1
	super._update_aim()
func _process(delta: float) -> void:
	actual_processes += 1
	super._process(delta)
	processed.emit()
