class_name MiniSlimeEnemy
extends CreatureEnemy

## 一代分裂幼体，使用共用生命周期；死亡不会继续请求生成。
func _combat_tick(delta: float) -> void:
	_move_chase(delta, combat_stop_distance)
	_touch_player()
