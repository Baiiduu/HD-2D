class_name PotBroodEnemy
extends CreatureEnemy

var rules: PotBroodDefinition

func configure_wave(context: Dictionary, data: WaveEnemyDefinition, warning: float) -> void:
	super.configure_wave(context, data, warning)
	rules = data as PotBroodDefinition

func _combat_tick(delta: float) -> void:
	_move_chase(delta, combat_stop_distance)
	_touch_player()

func _on_defeated() -> void:
	# 先登记两只一代幼体，再由父类发出死亡；不会提前清波。
	if request_spawn_by_id.is_valid():
		var side := Vector3.UP.cross(_look).normalized() * 0.4
		request_spawn_by_id.call(rules.child_enemy_id, 1, rules.split_delay, global_position + side)
		request_spawn_by_id.call(rules.child_enemy_id, 1, rules.split_delay, global_position - side)
	super._on_defeated()
