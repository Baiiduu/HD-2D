extends "res://tests/test_player_sword.gd"
## Compare exact reachability with the original sampler; no rendering acceptance.

class OriginalSword extends PlayerSword:
	func _can_reach(origin: Vector3, actor: WaveEnemy) -> bool:
		var height := _settings.height_tolerance if swinging else rules.height_tolerance
		if not _eligible(actor): return false
		var point := _path.ground_position(origin)
		var target := _path.ground_position(actor.global_position)
		if absf(point.y - target.y) > height or absf(actor.global_position.y - point.y) > height: return false
		var length := TerrainPath.horizontal_distance(point, target)
		var direction := (target - point).normalized()
		if _collision.ground_limit(_path, point, direction, length, point.y, height) < length - 0.00001: return false
		return _path.terrain.ray_clear(point + Vector3.UP * 0.45, target + Vector3.UP * 0.45, 1, [player.get_rid()])

class CountingPath extends TerrainPath:
	var projections := 0
	func ground_position(point: Vector3) -> Vector3:
		projections += 1
		return super.ground_position(point)

class CountingSurface extends RefCounted:
	var source: RefCounted
	var calls := 0
	func flat_ground(origin: Vector3, radius: float) -> bool:
		calls += 1
		return source.flat_ground(origin, radius)

func collector(script: GDScript) -> PlayerSword:
	var value: PlayerSword = script.new()
	value.player = player
	value.session = session
	value.rules = load("res://data/combat/scenes/world/player/basic_sword.tres")
	value._settings = value.rules.duplicate()
	value._stats = value.get_stats(true)
	value._stats.range = 3.952
	value._heading = Vector3.RIGHT
	value._flight_swing = true
	value._age = 0.06
	value._surface = session.get_attack_surface_query()
	var path := CountingPath.new()
	path.terrain = terrain
	path.data = terrain.data
	value._path = path
	return value

func contacts(value: PlayerSword) -> PackedByteArray:
	var rows := []
	for contact in value._pending_hits:
		var row := contact.duplicate()
		row.enemy = row.enemy.get_instance_id()
		rows.append(row)
	return var_to_bytes([value._hits.keys(), rows])

func compare_reach(current: PlayerSword, old: PlayerSword, target: WaveEnemy, label: String) -> void:
	for origin in [Vector3.ZERO, Vector3(-0.21, 0.03, 0.12)]:
		check(current._can_reach(origin, target) == old._can_reach(origin, target), "Exact live reachability: " + label)

func manual_checks() -> void:
	await reset()
	var actors: Array[WaveEnemy] = []
	for index in 80:
		var theta := TAU * float(index % 16) / 16.0
		var radius := 0.5 + float(index / 16) * 0.6
		actors.append(enemy(Vector3(cos(theta), 0.0, sin(theta)) * radius, 100000.0))
	var current := collector(PlayerSword)
	var old := collector(OriginalSword)
	for actor in actors: compare_reach(current, old, actor, "open flat ground")
	(current._path as CountingPath).projections = 0
	(old._path as CountingPath).projections = 0
	for value in [current, old]:
		for actor in actors: value._can_reach(Vector3.ZERO, actor)
	var before := (old._path as CountingPath).projections
	var after := (current._path as CountingPath).projections
	check(after == actors.size() * 2 and after < before * 0.3, "Certified flat ground needs only origin and target projections")
	print(JSON.stringify({"flat_sword_ground_reads":{"before":before,"after":after},"targets":actors.size()}))
	var surface := CountingSurface.new()
	surface.source = current._surface
	current._surface = surface
	for reverse in [false, true]:
		for angle in [120.0, 360.0]:
			for travel in [Vector3.ZERO, Vector3(0.23, 0.0, -0.19)]:
				surface.calls = 0
				for value in [current, old]:
					value._reverse = reverse
					value._stats.angle = angle
					value._hits.clear()
					value._pending_hits.clear()
					value._collect_hits(Vector3.ZERO, travel, 0.0, 1.0, true, 0.0, 0.1, 16.0, 0.5)
				check(contacts(current) == contacts(old), "Full sweeps retain exact targets, order, times and contact data")
				check(surface.calls <= 1, "The whole synchronous sweep shares one ground proof")
	check(current._flat_reach_state == -1, "No ground proof survives the synchronous sweep")
	var target := enemy(Vector3(2.5, 0, 0), 100000.0)
	terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, true)
	await settle()
	compare_reach(current, old, target, "water crossing")
	check(not current._can_reach(Vector3.ZERO, target), "Water still blocks the real sword")
	terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, false)
	terrain.data.set_overlay(Vector2i(0, 2), TerrainData.OVERLAY_WATER, true)
	await settle()
	compare_reach(current, old, target, "off-path water rejects only the proof")
	check(current._can_reach(Vector3.ZERO, target), "Off-path water cannot reject a valid exact fallback")
	terrain.data.set_overlay(Vector2i(0, 2), TerrainData.OVERLAY_WATER, false)
	terrain.data.set_level(Vector2i(1, 0), 1)
	await settle()
	compare_reach(current, old, target, "raised ground and missing support")
	terrain.data.set_level(Vector2i(1, 0), 0)
	await settle()
	var wall := box(Vector3(0.75, 0.6, 0), Vector3(0.04, 1.2, 4.0))
	await settle()
	compare_reach(current, old, target, "thin live wall")
	check(not current._can_reach(Vector3.ZERO, target), "Flat proof never substitutes for a real wall check")
	wall.position.x = -4.0
	await settle()
	compare_reach(current, old, target, "moved wall")
	check(current._can_reach(Vector3.ZERO, target), "Moved walls are observed immediately after physics synchronization")
	current._surface = null
	compare_reach(current, old, target, "no shared surface proof")
	wall.free()
	current.free()
	old.free()

func idle_checks() -> void: pass
func attack_speed_checks() -> void: pass
func flight_checks() -> void: pass
func freeze_checks() -> void: pass
func input_and_art_checks() -> void: pass
func score_checks() -> void: pass
