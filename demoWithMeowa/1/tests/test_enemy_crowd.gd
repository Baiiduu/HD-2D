extends SceneTree

class OpenPath extends TerrainPath:
	func shared_pursuit_route(from: Vector3, goal: Vector3) -> PackedVector3Array:
		return PackedVector3Array([from, goal])
	func ground_position(point: Vector3) -> Vector3:
		return Vector3(point.x, 0, point.z)

class LegacySlime extends SlimeEnemy:
	func _crowd_direction(desired: Vector3) -> Vector3:
		if desired.is_zero_approx(): return desired
		var force := Vector3.ZERO
		for other in spatial_index.nearby(global_position, 0.75):
			if other == self: continue
			var offset := global_position - other.global_position
			offset.y = 0
			var distance := offset.length()
			if distance > 0.01: force += offset / distance * (0.75 - distance)
		return (desired + force * 1.5).normalized()

var checks := 0
var failures := 0
var world: Node3D
var target: CharacterBody3D
var index := WaveEnemySpatialIndex.new()
var path := OpenPath.new()
var enemies: Array[SlimeEnemy] = []

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func capsule(body: CharacterBody3D, radius: float, height: float) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position.y = height * 0.5
	body.add_child(collision)

func mob(point: Vector3, legacy := false) -> SlimeEnemy:
	var enemy := LegacySlime.new() if legacy else SlimeEnemy.new()
	enemy.wave_mode = true
	enemy.target = target
	enemy.navigation = path
	enemy._path = path
	enemy.spatial_index = index
	enemy.spawn_delay = 0
	enemy.move_speed = 1.7
	enemy.attack_damage = 0
	enemy.damage_player = func(_amount): return false
	enemy.position = point
	enemy.collision_layer = 2
	enemy.collision_mask = 1
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	enemy.add_child(sprite)
	capsule(enemy, 0.28, 0.7)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemies.append(enemy)
	index.update(enemy)
	return enemy

func clear_mobs() -> void:
	for enemy in enemies: enemy.free()
	enemies.clear()
	index.clear()

func step(count: int) -> void:
	for frame in count:
		await physics_frame
		for enemy in enemies:
			enemy._combat_tick(1.0 / 60.0)
			index.update(enemy)

func density() -> Dictionary:
	var nearest: Array[float] = []
	var mean := 0.0
	for enemy in enemies:
		var distance := INF
		for other in enemies:
			if other != enemy: distance = minf(distance, TerrainPath.horizontal_distance(enemy.global_position, other.global_position))
		nearest.append(distance)
		mean += TerrainPath.horizontal_distance(enemy.global_position, target.global_position)
	nearest.sort()
	return {"minimum": nearest[0], "median": nearest[nearest.size() / 2], "mean_target": mean / enemies.size()}

func pair_checks() -> void:
	var back := mob(Vector3(0, 0.02, 2))
	var front := mob(Vector3(0, 0.02, 1.2))
	var desired := Vector3.FORWARD
	var actual := back._crowd_direction(desired)
	check(actual.length() < 0.8 and actual.z < 0.0, "前排挡住时后排实际减速，仍保留向前推进")
	check(front._crowd_direction(Vector3.ZERO).length() > 0.0, "停止追击的怪物仍能整理与后排的间距")
	front.position = back.position
	index.update(front)
	var first := index.separation(back, 1.0)
	var second := index.separation(front, 1.0)
	check(first.is_finite() and first.length() > 0 and first.is_equal_approx(-second), "完全同点会成对分开，不出现零向量或 NaN")
	front.position.y = 3
	index.update(front)
	check(index.separation(back, 1.0).is_zero_approx(), "不同高度的怪物不隔层互推")
	front.position = back.position + Vector3.RIGHT * 1.4
	front.separation_radius = 2.0
	index.update(front)
	check(index.separation(back, 1.0).x < 0.0, "混合体型按双方间距查邻居，不漏查大体型")
	front.spawn_delay = 1
	index.update(front)
	check(index.separation(back, 1.0).is_zero_approx(), "出场预告不推动现有怪物")
	back.separation_strength = 0
	check(back._crowd_direction(desired) == desired, "避让强度为零时可独立关闭聚群调整")
	clear_mobs()

func simulate(legacy: bool) -> Dictionary:
	target.position = Vector3.ZERO
	for row in 8:
		for column in 16: mob(Vector3((column - 7.5) * 0.85, 0.02, 4 + row * 0.85), legacy)
	await step(480)
	var result := density()
	check(enemies.all(func(enemy): return enemy.global_position.is_finite() and enemy.velocity.is_finite()), "128 只持续追击保持有限位置和速度")
	print("Crowd legacy=", legacy, " ", result)
	return result

func facing_checks() -> void:
	var previous: Array[int] = []
	for enemy in enemies: previous.append(enemy._facing_index(Vector3.RIGHT, Vector3.BACK))
	var micro_turns := 0
	var turns := 0
	for frame in 120:
		var points: Array[Vector3] = []
		for enemy in enemies: points.append(enemy.global_position)
		await step(1)
		for number in enemies.size():
			var facing := enemies[number]._facing_index(Vector3.RIGHT, Vector3.BACK)
			if facing != previous[number]:
				turns += 1
				if TerrainPath.horizontal_distance(points[number], enemies[number].global_position) < 0.003: micro_turns += 1
			previous[number] = facing
	check(micro_turns <= 4 and turns <= 16, "128 只围住静止目标时不被微小避让反复切朝向")
	check(enemies.all(func(enemy): return enemy._look.dot((target.global_position - enemy.global_position).normalized()) > 0.98), "包围圈内的怪物稳定面对目标")
	print("Crowd facing: turns=", turns, " micro_turns=", micro_turns)
	for actor: SlimeEnemy in [SlimeEnemy.new(), CreatureEnemy.new()]:
		actor._look = Vector3(sin(deg_to_rad(20.0)), 0, cos(deg_to_rad(20.0)))
		check(actor._facing_index(Vector3.RIGHT, Vector3.BACK) == 0, "初始显示选择最近方向")
		var stable := true
		for angle in [24.0, 21.0, 25.0, 20.0, 24.0]:
			actor._look = Vector3(sin(deg_to_rad(angle)), 0, cos(deg_to_rad(angle)))
			stable = stable and actor._facing_index(Vector3.RIGHT, Vector3.BACK) == 0
		check(stable, "相邻八方向分界附近有余量，不来回翻转")
		actor._look = Vector3(sin(deg_to_rad(35.0)), 0, cos(deg_to_rad(35.0)))
		check(actor._facing_index(Vector3.RIGHT, Vector3.BACK) == 1, "真正转向无需等待计时器")
		actor._look = Vector3.FORWARD
		check(actor._facing_index(Vector3.RIGHT, Vector3.BACK) == 4, "突发反向仍立即显示正确方向")
		actor._look = Vector3.BACK
		var follows_camera := true
		for number in 8:
			var basis := Basis(Vector3.UP, number * TAU / 8.0)
			follows_camera = follows_camera and actor._facing_index(basis.x, basis.z) == posmod(-number, 8)
		check(follows_camera, "Q/E 八个方向仍随镜头重新投影，独立于世界朝向")
		actor.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	floor_collision.shape = box
	floor_collision.position.y = -0.1
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	target = CharacterBody3D.new()
	capsule(target, 0.3, 1.0)
	world.add_child(target)
	pair_checks()
	var legacy := await simulate(true)
	clear_mobs()
	var current := await simulate(false)
	check(current.minimum > 0.45 and current.median > 0.6, "128 只围聚时保留可分辨个体的身体间距")
	check(current.median > legacy.median * 2.0, "相同追击与数量下显著减少旧版身体堆叠")
	check(current.mean_target < 5.0, "保留紧凑人海，未将怪群疏散到远处")
	await facing_checks()
	target.position.z = -3
	var distance: float = density().mean_target
	await step(150)
	check(density().mean_target < distance - 0.5, "人物移动后整片怪群继续推进，不锁死为静态圆阵")
	for resource in ["wave_slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		var definition: WaveMeleeEnemyDefinition = load("res://data/enemies/" + resource + ".tres")
		check(definition.validation_error().is_empty(), "正式混合怪物资源合法：" + resource)
	clear_mobs()
	world.queue_free()
	for frame in 3: await process_frame
	print("Enemy crowd: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
