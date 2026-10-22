extends "res://tests/test_spatial_index_reuse.gd"

## 固定优化前的轮廓算法，比较成员顺序、几何结果及体型读取次数。
class LegacyRegions extends EnemyPushWave:
	func _region_for(seed: WaveEnemy, heading: Vector3) -> Dictionary:
		var id := seed.get_instance_id()
		if _regions.has(id): return _regions[id]
		var members: Array[WaveEnemy] = [seed]
		var visited: Dictionary[int, bool] = {id: true}
		var position := seed.global_position
		var cursor := 0
		# 仅首次命中时，通过局部空间索引找相连怪群；断开的远处怪不拉长椭圆。
		while seed.spatial_index and cursor < members.size():
			var current := members[cursor]
			cursor += 1
			for other in seed.spatial_index.nearby(current.global_position, rules.push_group_link_distance):
				var other_id := other.get_instance_id()
				if visited.has(other_id) or other.dead or other.spawn_delay > 0.0: continue
				if absf(other.global_position.y - position.y) > rules.push_height_tolerance: continue
				if TerrainPath.horizontal_distance(other.global_position, position) > rules.push_group_search_radius: continue
				_ray.from = current.global_position + Vector3.UP * 0.45
				_ray.to = other.global_position + Vector3.UP * 0.45
				if not seed.get_world_3d().direct_space_state.intersect_ray(_ray).is_empty(): continue
				visited[other_id] = true
				members.append(other)
		var center := Vector3.ZERO
		for member in members: center += member.global_position
		center /= members.size()
		var xx := 0.0
		var zz := 0.0
		var xz := 0.0
		for member in members:
			var offset := member.global_position - center
			xx += offset.x * offset.x
			zz += offset.z * offset.z
			xz += offset.x * offset.z
		var angle := 0.5 * atan2(2.0 * xz, xx - zz)
		var u := Vector3(cos(angle), 0.0, sin(angle))
		var v := Vector3(-u.z, 0.0, u.x)
		var radii := Vector2(0.8, 0.8)
		var arrival_spacing := 0.0
		if xx + zz < 0.0001:
			var radial := Vector3(heading.z, 0.0, -heading.x).normalized() * (1.0 if rules.clockwise else -1.0)
			if radial.is_zero_approx(): radial = Vector3.RIGHT
			center -= radial * radii.x
		for member in members:
			var offset := member.global_position - center
			var margin := member.get_crowd_body_radius() + rules.push_group_edge_margin
			arrival_spacing = maxf(arrival_spacing, member.get_crowd_body_radius() * 2.1)
			radii.x = maxf(radii.x, absf(offset.dot(u)) + margin)
			radii.y = maxf(radii.y, absf(offset.dot(v)) + margin)
		var scale := 1.0
		for member in members:
			var offset := member.global_position - center
			var margin := member.get_crowd_body_radius() + rules.push_group_edge_margin
			scale = maxf(scale, Vector2((absf(offset.dot(u)) + margin) / radii.x, (absf(offset.dot(v)) + margin) / radii.y).length())
		var ids := PackedInt64Array()
		for member in members: ids.append(member.get_instance_id())
		var region := {"center": center, "u": u, "v": v, "radii": radii * scale, "members": ids, "arrival_spacing": arrival_spacing}
		for member in members: _regions[member.get_instance_id()] = region
		return region

var excluded: Dictionary[int, bool] = {}
var buffer: Array[WaveEnemy] = []

func probe(point: Vector3) -> ProbeEnemy:
	var actor := ProbeEnemy.new()
	actor.position = point
	actor.spawn_delay = 0.0
	actor.spatial_index = actual
	actor.body = 0.2 + enemies.size() % 4 * 0.04
	world.add_child(actor)
	actor.set_physics_process(false)
	enemies.append(actor)
	update(actor)
	return actor

func compare_query(point: Vector3, radius: float, label: String) -> void:
	var expected: Array[WaveEnemy] = []
	for actor in actual.nearby(point, radius):
		if not excluded.has(actor.get_instance_id()): expected.append(actor)
	actual.nearby_into(point, radius, excluded, buffer)
	check(buffer == expected, label + ": same live candidates and order")

func query_checks() -> void:
	for pattern in 3:
		excluded.clear()
		for index in enemies.size():
			if pattern == 2 or (pattern == 1 and index % 2 == 0):
				excluded[enemies[index].get_instance_id()] = true
		for actor in enemies:
			for radius in [0.0, 0.00001, 0.35, 1.5, 4.0]:
				compare_query(actor.position, radius, "exclusion %d" % pattern)
	# 同格移动尚未同步索引也须读取实时位置，不能复用旧坐标。
	excluded.clear()
	var moved := enemies[0]
	moved.position += Vector3(0.15, 0, 0.15)
	compare_query(moved.position, 0.01, "live same-cell movement")
	update(moved)
	moved.position += Vector3(-2, 0, 0)
	update(moved)
	compare_query(moved.position, 0.01, "cross-cell movement")
	moved.dead = true
	compare_query(moved.position, 3.0, "dead without removal")
	moved.dead = false
	actual.remove(moved)
	legacy.remove(moved)
	compare_query(moved.position, 3.0, "removed slot")
	update(moved)
	compare_query(moved.position, 3.0, "reused slot")
	compare_query(Vector3(100, 0, 100), 0.1, "empty query clears reused buffer")
	excluded.clear()

func compare_region(seed: ProbeEnemy, label: String) -> void:
	var rules := PlayerRicochetRules.new()
	for actor in enemies: actor.body_reads = 0
	var expected := LegacyRegions.new(rules).region_for(seed, Vector3.RIGHT)
	var old_reads := 0
	for actor in enemies:
		old_reads += actor.body_reads
		actor.body_reads = 0
	var wave := EnemyPushWave.new(rules)
	var result := wave.region_for(seed, Vector3.RIGHT)
	for field in ["members", "center", "u", "v", "radii", "arrival_spacing"]:
		check(result[field] == expected[field], label + ": exact " + field)
	var reads := 0
	for actor in enemies: reads += actor.body_reads
	check(reads == result.members.size() and old_reads == reads * 3,
		label + ": one body read per member instead of three")
	var cached := wave.region_for(seed, Vector3.FORWARD)
	var cached_reads := 0
	for actor in enemies: cached_reads += actor.body_reads
	check(is_same(cached, result) and cached_reads == reads,
		label + ": same-flight cache avoids repeated geometry")
	check(wave._nearby.is_empty(), label + ": query workspace releases enemy references")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	for row in 8:
		for column in 8: probe(Vector3(column * 0.6, 0, row * 0.6))
	probe(Vector3(0, 2, 0))
	var warning := probe(Vector3(0.1, 0, 0.1))
	warning.spawn_delay = 1.0
	probe(Vector3(13, 0, 0))
	query_checks()
	compare_region(enemies[1], "mixed bodies and eligibility")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.02, 1.2, 12)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.position = Vector3(1.5, 0.6, 2)
	for frame in 2:
		await physics_frame
		await process_frame
	compare_region(enemies[1], "wall splits connected group")
	wall.position.x = 8.0
	for frame in 2:
		await physics_frame
		await process_frame
	compare_region(enemies[1], "moved wall checked again on next wave")
	for actor in enemies:
		actor.position = Vector3.ZERO
		actor.spawn_delay = 0.0
		update(actor)
	compare_region(enemies[0], "coincident group")
	actual.clear()
	legacy.clear()
	buffer.clear()
	for actor in enemies: actor.free()
	enemies.clear()
	world.free()
	print("Crowd query reuse: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
