extends WavePrototype

## 只隔离波次编排和界面；沿用真实空间索引、冻结与攻击资格接口。
func _ready() -> void:
	set_physics_process(false)

func combat_active() -> bool:
	return phase == Phase.BATTLE and not combat_frozen and is_instance_valid(player) and player.current_health > 0.0
