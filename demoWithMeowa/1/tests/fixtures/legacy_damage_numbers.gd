extends DamageNumbers

## Frozen reverse update/removal order for functional comparison.
func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := maxf(0.0, (now - _last_tick) / 1000000.0) if _last_tick > 0 else 0.0
	_last_tick = now
	var camera := get_viewport().get_camera_3d()
	# 切入短顿的一帧仍可能带有旧 delta，不能用新倍率反推真实时长。
	if camera is FollowCamera and camera.hit_stop_active: delta = real_delta
	for index in range(_active.size() - 1, -1, -1):
		var number := _active[index]
		if not number.advance(delta, camera):
			_active.remove_at(index)
			_recycle(number)
	if _active.is_empty(): set_process(false)

