extends "res://tests/test_damage_numbers.gd"

class CurrentPool extends DamageNumbers:
	var recycled: Array[int] = []
	var after_recycle: Callable
	func _recycle(number: DamageNumber) -> void:
		recycled.append(number.event.target_id)
		super._recycle(number)
		if after_recycle.is_valid(): after_recycle.call()
class OldPool extends "res://tests/fixtures/legacy_damage_numbers.gd":
	var recycled: Array[int] = []
	var after_recycle: Callable
	func _recycle(number: DamageNumber) -> void:
		recycled.append(number.event.target_id)
		super._recycle(number)
		if after_recycle.is_valid(): after_recycle.call()

func state(pool: DamageNumbers) -> Array:
	var result := []
	for number in pool._active:
		result.append([number.event.target_id, number.age, number.position, number.scale, number.rotation, number.opacity, number.visible, number.lane, number._text])
	var idle_order := []
	for number in pool._idle: idle_order.append(number.get_meta(&"birth_slot", -1))
	return [result, pool.get_pool_stats(), pool._lanes.duplicate(true), pool.get("recycled"), idle_order]

func fill(pool: DamageNumbers, pattern: int) -> void:
	for index in 12:
		pool.present(hit(index % 3))
		pool._active[-1].set_meta(&"birth_slot", index)
		pool._active[-1].age = 0.79 if (index + pattern) % 3 != 0 else 0.12

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 5, 10)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	for pattern in 3:
		var current = CurrentPool.new()
		var old = OldPool.new()
		for pool in [current, old]:
			pool.number_prewarm = 0
			pool.number_idle_limit = 8
			pool.number_styles = load("res://data/combat/scenes/world/configuration.tres").number_styles
			world.add_child(pool)
			fill(pool, pattern)
		for delta in [0.0, 0.05, 0.1, 0.4, 1.0]:
			current._process(delta)
			old._process(delta)
			check(state(current) == state(old), "混合过期的数字状态、存活顺序、回收顺序和分槽逐项保持")
		for pool in [current, old]:
			pool.present(hit(80))
			pool._active[0].age = 0.79
			pool.after_recycle = func():
				pool.after_recycle = Callable()
				pool.present(hit(81))
		current._process(0.1)
		old._process(0.1)
		check(state(current) == state(old) and current._active[0].event.target_id == 81 and current._active[0].age == 0.0, "回收回调的新命中保留在尾部，不被提前推进或覆盖")
		current.clear()
		current.present(hit(90))
		current.present(hit(91))
		current._active[-1].age = 0.79
		current.after_recycle = func():
			current.after_recycle = Callable()
			current.clear()
			current.present(hit(99))
		current._process(0.1)
		check(current._active.size() == 1 and current._active[0].event.target_id == 99 and current._active[0].age == 0.0 and current.get_pool_stats().active == 1, "回收中清空或重开时停止旧批次，不覆盖新数字")
		current.free()
		old.free()
	world.free()
	print("Damage number compaction: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
