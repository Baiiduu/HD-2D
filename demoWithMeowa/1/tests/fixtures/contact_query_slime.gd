extends SlimeEnemy

var sight_queries := 0

func _can_see_target() -> bool:
	sight_queries += 1
	return super._can_see_target()
