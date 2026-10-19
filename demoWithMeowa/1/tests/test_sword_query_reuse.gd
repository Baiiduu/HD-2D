extends "res://tests/test_player_sword.gd"

const Legacy := preload("res://tests/fixtures/legacy_sword_sweep_oracle.gd")

class CountingSword extends PlayerSword:
	var eligibility_checks := 0
	func _eligible(actor: WaveEnemy) -> bool:
		eligibility_checks += 1
		return super._eligible(actor)

class CountingLegacy extends "res://tests/fixtures/legacy_sword_sweep_oracle.gd":
	var eligibility_checks := 0
	func _eligible(actor: WaveEnemy) -> bool:
		eligibility_checks += 1
		return super._eligible(actor)

class CountingPath extends TerrainPath:
	var projections := 0
	func ground_position(point: Vector3) -> Vector3:
		projections += 1
		return super.ground_position(point)

class ClearGround extends ProjectileCollision:
	func ground_limit(_path: TerrainPath, _start: Vector3, _direction: Vector3, distance: float, _plane: float, _tolerance: float) -> float:
		return distance

class SharedQuerySession extends WavePrototype:
	var candidates: Array[WaveEnemy] = []
	func _ready() -> void: set_physics_process(false)
	func combat_active() -> bool: return true
	func get_nearby_enemies(_point: Vector3, _radius: float) -> Array[WaveEnemy]:
		return candidates

func collector(script: GDScript, heading := Vector3.FORWARD, reverse := false) -> PlayerSword:
	var value: PlayerSword = script.new()
	value.player = player
	value.session = session
	value.rules = sword.rules
	value._settings = value.rules.duplicate()
	value._stats = value.get_stats(true)
	value._path = session._path
	value._heading = heading
	value._reverse = reverse
	value._flight_swing = true
	return value

func signature(value: PlayerSword) -> PackedByteArray:
	var hits := []
	for hit in value._pending_hits:
		var row: Dictionary = hit.duplicate()
		row.enemy = hit.enemy.get_instance_id()
		hits.append(row)
	return var_to_bytes([value._hits.keys(), hits])

func compare_sweep(label: String) -> void:
	for reverse in [false, true]:
		for heading in [Vector3.FORWARD, Vector3.RIGHT, Vector3(0.4, 0, -1).normalized()]:
			var current := collector(CountingSword, heading, reverse)
			var old := collector(Legacy, heading, reverse)
			for sweep in [[Vector3(0, 0.03, 0), Vector3(0.4, 0.03, -0.2), 0.0, 0.5], [Vector3(0.4, 0.03, -0.2), Vector3(0.7, 0.03, -0.25), 0.5, 1.0]]:
				for value in [current, old]: value._collect_hits(sweep[0], sweep[1], sweep[2], sweep[3], true, 0.0, 0.05, 12.0, 0.5)
				check(signature(current) == signature(old), "命中对象、顺序、方向、时刻和去重与原规则逐字节一致：%s / %s / %s" % [label, reverse, heading])
			current.free()
			old.free()

func manual_checks() -> void:
	await reset()
	for x in [-0.8, -1.0, -1.2]: enemy(Vector3(x, 0, 0))
	var current := collector(CountingSword) as CountingSword
	var old := collector(CountingLegacy) as CountingLegacy
	for value in [current, old]: value._collect_hits(Vector3(0, 0.03, 0), Vector3(0, 0.03, 0), 0.0, 1.0, true, 0.0, 0.1)
	check(current._pending_hits.size() == 3 and signature(current) == signature(old), "起始刀锋覆盖多个目标时，仍按原顺序完整结算")
	check(current.eligibility_checks <= 6, "已命中的目标立即退出本刀后续切片，不反复检查")
	check(old.eligibility_checks == 273, "冻结的旧规则保留重复工作的独立对照")
	print(JSON.stringify({"sword_eligibility_checks":{"old":old.eligibility_checks,"new":current.eligibility_checks},"targets":3,"sweep_slices":90}))
	var recorded := current.eligibility_checks
	current._collect_hits(Vector3(0, 0.03, 0), Vector3(0, 0.03, 0), 0.0, 1.0, true, 0.1, 0.1)
	check(current.eligibility_checks - recorded <= 3 and current._pending_hits.size() == 3, "下一段也只剔除一次已命中目标，不重复伤害")
	var path := CountingPath.new()
	path.terrain = terrain
	path.data = terrain.data
	current._path = path
	current._collision = ClearGround.new()
	check(current._can_reach(Vector3(0, 0.03, 0), session.enemies[0]), "独立地表提供器继续决定可达性")
	check(path.projections == 2, "一次可达性查询只投地人物和目标各一次")
	current.free()
	old.free()
	var shared := SharedQuerySession.new()
	shared.candidates.assign(session.enemies)
	world.add_child(shared)
	current = collector(CountingSword)
	current.session = shared
	var expected_candidates := shared.candidates.duplicate()
	current._collect_hits(Vector3(0, 0.03, 0), Vector3(0, 0.03, 0), 0.0, 1.0, true, 0.0, 0.1)
	check(shared.candidates == expected_candidates, "自定义公共查询返回的共享列表保持只读")
	current.free()
	shared.free()
	await reset()
	for point in [Vector3(-1, 0, -0.2), Vector3(-0.5, 0, -1), Vector3(0.4, 0, -0.6), Vector3(1, 0, 0), Vector3(0.7, 0, -1.1)]: enemy(point)
	compare_sweep("静止与高速移动的连续挥扫")
	var wall := box(Vector3(0, 0.6, -0.5), Vector3(5, 1.2, 0.025))
	await settle()
	compare_sweep("动态薄墙挡住部分目标")
	wall.queue_free()
	await settle()
	compare_sweep("移除挡墙后立即恢复")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, true)
	await settle()
	compare_sweep("真实水面阻断")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, false)
	terrain.data.set_level(Vector2i.ZERO, 1)
	await settle()
	compare_sweep("真实高差阻断")

func attack_speed_checks() -> void: pass
func flight_checks() -> void: pass
func freeze_checks() -> void: pass
func legacy_clip(origin: Vector3, heading: Vector3, radius: float, angle: float, reverse: bool, rules: PlayerSwordRules) -> Array:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var basis := Basis(Vector3.UP, atan2(-heading.x, -heading.z))
	var flat: bool = sword._surface.flat_ground(origin, radius)
	var half := deg_to_rad(angle * 0.5)
	var collision := ProjectileCollision.new()
	for angular in 65:
		var theta := lerpf(-half, half, float(angular) / 64)
		var radial := Vector3(sin(theta), 0, -cos(theta))
		var direction := basis * radial
		var limit := radius
		if not flat: limit = collision.ground_limit(session._path, origin, direction, radius, origin.y, rules.height_tolerance)
		var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.45, origin + Vector3.UP * 0.45 + direction * limit, 1, [player.get_rid()])
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): limit = maxf(0.0, origin.distance_to(hit.position - Vector3.UP * 0.45) - 0.02)
		for ring in 5:
			var distance := limit * float(ring) / 4
			var point := radial * distance
			point.y = rules.effect_height if flat else session._path.ground_position(origin + basis * point).y - origin.y + rules.effect_height
			vertices.append(point)
			var pixel := Vector2(radial.x * (-1.0 if reverse else 1.0), radial.z) * distance / radius
			uvs.append(Vector2(0.5, 0.5) + pixel / Vector2(2, 2))
	return [vertices.to_byte_array(), uvs.to_byte_array()]

func input_and_art_checks() -> void:
	terrain.data.set_level(Vector2i.ZERO, 0)
	await reset()
	var rules: PlayerSwordRules = load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate()
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.025, 1.2, 6))
	await settle()
	for reverse in [false, true]:
		for angle in [180.0, 80.0, 120.0, 180.0]:
			for heading in [Vector3.RIGHT, Vector3(0.4, 0, -1).normalized()]:
				for radius in [1.52, 2.2]:
					sword._effect.display(Vector3.ZERO, heading, radius, angle, reverse, null, 0.05, rules, session._path, sword._surface, [player.get_rid()])
					var arrays := sword._effect.mesh.surface_get_arrays(0)
					check([(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array(), (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).to_byte_array()] == legacy_clip(Vector3.ZERO, heading, radius, angle, reverse, rules), "复用角度模板和射线对象保留全部顶点与 UV：%s / %s / %s" % [reverse, angle, radius])
	wall.position.x = -0.7
	await settle()
	sword._effect.display(Vector3.ZERO, Vector3.LEFT, 1.52, 180.0, false, null, 0.05, rules, session._path, sword._surface, [player.get_rid()])
	var arrays := sword._effect.mesh.surface_get_arrays(0)
	check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array() == legacy_clip(Vector3.ZERO, Vector3.LEFT, 1.52, 180.0, false, rules)[0], "墙体移入另一侧时实时重查，不沿用旧裁切结果")
	wall.queue_free()
