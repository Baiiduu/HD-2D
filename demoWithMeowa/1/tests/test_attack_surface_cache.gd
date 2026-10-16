extends SceneTree

var checks := 0
var failures := 0

class PreciseSurface extends RefCounted:
	func flat_ground(_origin: Vector3, _radius: float) -> bool:
		return false

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func settle(count := 3) -> void:
	for frame in count: await physics_frame

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	await settle(12)
	var wave: WavePrototype = world.get_node("WavePrototype")
	var player: Player = world.get_node("Player")
	var fan: FanAutoAttack = wave.get_node("FanAutoAttack")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	fan.set_physics_process(false)
	player.global_position = wave.global_position + Vector3.UP * 0.03
	var skills: RunSkillManager = wave.get_node("RunSkillManager")
	skills._levels[&"fan_slash"] = 1
	fan.apply_skill_level(1)
	check(wave.start_run(), "Real battle starts")
	wave._spawn_queue.clear()
	check(wave._spawn_enemy(), "A living target keeps the battle active")
	var enemy: WaveEnemy = wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.health = 10000
	check(fan.apply_skill_level(7), "Dual rotation is available")
	var query := wave.get_attack_surface_query()
	var open_ground := Vector3.INF
	for point_id in wave._path.graph.get_point_ids():
		var point := wave._path.graph.get_point_position(point_id)
		if wave.battle_area.has_point(Vector2(point.x, point.z)) and query.unclipped_flat(point, fan.get_attack_stats().range):
			open_ground = point
			break
	check(open_ground.is_finite(), "The current map has an unobstructed flat test position")
	player.global_position = open_ground + Vector3.UP * 0.03
	enemy.global_position = player.global_position + Vector3.FORWARD * 1.5
	fan.audio_enabled = false
	fan.knockback_distance = 0
	fan._physics_process(1.0 / 60.0)
	var mesh := fan._mesh.mesh
	var basis := fan._mesh.global_basis
	check(mesh == fan._extra_meshes[0].mesh, "Both blades share the same flat mesh")
	check(mesh.surface_get_array_len(0) == 125 and mesh.surface_get_array_index_len(0) == 576, "Shared vertices preserve all 192 triangles")
	for frame in 90: fan._physics_process(1.0 / 60.0)
	check(fan._mesh.mesh == mesh and fan._extra_meshes[0].mesh == mesh and fan._mesh.global_basis != basis, "Rotation changes the transform without recreating geometry")
	player.global_position.x += 0.2
	fan._physics_process(1.0 / 60.0)
	check(fan._mesh.mesh == mesh and fan.global_position.distance_to(wave._ground_target()) < 0.001, "Movement reuses geometry while following the player")
	check(query == wave.get_attack_surface_query(), "All attacks retrieve the same battle query service")
	var origin := wave._ground_target()
	check(query.unclipped_flat(origin, fan.get_attack_stats().range), "Open battle ground permits mesh reuse")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 2, 0.15)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = origin + Vector3(0, 0.5, -0.8)
	await settle()
	check(not query.unclipped_flat(origin, fan.get_attack_stats().range), "A new wall invalidates flat reuse immediately")
	check(query.flat_ground(origin, fan.get_attack_stats().range), "Walls do not invalidate flat ground heights")
	var stats := fan.get_attack_stats()
	for degrees in [0, 45, 90, 135, 180, 270]:
		var orientation := Basis(Vector3.UP, deg_to_rad(degrees))
		var fast := fan._build_effect_mesh(origin, orientation, stats, false).surface_get_arrays(0)
		fan._surface_query = PreciseSurface.new()
		var reference := fan._build_effect_mesh(origin, orientation, stats, false).surface_get_arrays(0)
		fan._surface_query = query
		check((fast[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array() == (reference[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array()
			and (fast[Mesh.ARRAY_TEX_UV] as PackedVector2Array).to_byte_array() == (reference[Mesh.ARRAY_TEX_UV] as PackedVector2Array).to_byte_array(),
			"Flat ground beside a wall preserves exact clipped vertices and UVs at %d degrees" % degrees)
	fan._locked_basis = Basis.IDENTITY
	fan._update_mesh(origin)
	var clipped: PackedVector3Array = fan._mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var reach := 0.0
	for vertex in clipped: reach = maxf(reach, -vertex.z)
	check(reach < 0.8 and fan._mesh.mesh != mesh, "Fallback geometry stops at the wall")
	var clipped_mesh := fan._mesh.mesh
	fan._locked_basis = Basis(Vector3.UP, PI / 4)
	fan._update_mesh(origin)
	var refreshed := fan._mesh.mesh.surface_get_arrays(0)
	var freshly_built := fan._build_effect_mesh(origin, fan._locked_basis, stats, false).surface_get_arrays(0)
	check((refreshed[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array() == (freshly_built[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array()
		and (refreshed[Mesh.ARRAY_TEX_UV] as PackedVector2Array).to_byte_array() == (freshly_built[Mesh.ARRAY_TEX_UV] as PackedVector2Array).to_byte_array(),
		"Updating clipped buffers preserves all current vertices and UVs")
	if DisplayServer.get_name() != "headless":
		check(fan._mesh.mesh == clipped_mesh, "Clipped rotation reuses the same GPU mesh resource")
	wall.global_position.x += 20
	await settle()
	fan._update_mesh(origin)
	check(fan._mesh.mesh == mesh, "Moving the wall away restores the original cached mesh")
	wall.free()
	# 用独立运行时地形验证缓存失效，不改写正式地图数据。
	var fixture := Terrain.new()
	fixture.position = Vector3(200, 0, 200)
	fixture.data = TerrainData.new()
	fixture.data.size = Vector2i.ZERO
	fixture.data.resize(Vector2i(-3, -3), Vector2i(6, 6))
	world.add_child(fixture)
	var local_query: RefCounted = WavePrototype.ATTACK_SURFACE_QUERY.new()
	var excluded: Array[RID] = [player.get_rid()]
	local_query.configure(fixture, excluded)
	check(local_query.unclipped_flat(fixture.global_position, 1.0), "Independent flat terrain is accepted")
	fixture.data.set_overlay(Vector2i.RIGHT, TerrainData.OVERLAY_WATER, true)
	check(not local_query.unclipped_flat(fixture.global_position, 1.0), "Water edits invalidate same-frame terrain eligibility")
	fixture.data.set_overlay(Vector2i.RIGHT, TerrainData.OVERLAY_WATER, false)
	fixture.data.set_level(Vector2i.RIGHT, 1)
	check(not local_query.unclipped_flat(fixture.global_position, 1.0), "Terrace edits require exact clipping")
	check(not local_query.flat_ground(fixture.global_position, 1.0), "Different heights cannot use flat ground sampling")
	fixture.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_RAMP, true)
	check(not local_query.unclipped_flat(fixture.global_position + Vector3.UP * 0.4, 1.0), "A ramp never reuses a flat mesh")
	var navigation := TerrainPath.new()
	navigation.terrain = fixture
	navigation.data = fixture.data
	var corners := fixture._corner_heights(Vector2i.ZERO)
	check(navigation._surface_heights(Vector2i.ZERO) == corners, "Cached ramp corners preserve exact heights")
	var sample_position := fixture.to_global(Vector3(0.2, 100.0, 0.1))
	var fraction := Vector2(0.2, 0.1) / fixture.data.cell_size + Vector2.ONE * 0.5
	var expected := lerpf(lerpf(corners[0], corners[1], fraction.x), lerpf(corners[3], corners[2], fraction.x), fraction.y)
	check(is_equal_approx(navigation.ground_position(sample_position).y, expected), "Cached ground projection preserves ramp interpolation")
	fixture.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_BRIDGE, true)
	corners = fixture._corner_heights(Vector2i.ZERO)
	for index in corners.size(): corners[index] += fixture.data.layer_height
	check(navigation._surface_heights(Vector2i.ZERO) == corners, "Bridge edits invalidate cached corner heights in the same frame")
	fixture.data.set_level(Vector2i.ZERO, 2)
	check(is_equal_approx(navigation._surface_heights(Vector2i.ZERO)[0], 3.0 * fixture.data.layer_height), "Height edits invalidate corner samples immediately")
	fixture.data.layer_height = 0.6
	check(is_equal_approx(navigation._surface_heights(Vector2i.ZERO)[0], 1.8), "Layer height changes invalidate samples without requiring a signal")
	fixture.data.heights[fixture.data._index(Vector2i.ZERO)] = TerrainData.HEIGHT_OFFSET + 3
	await settle()
	check(is_equal_approx(navigation._surface_heights(Vector2i.ZERO)[0], 2.4), "Samples expire at the next physics frame")
	var original_data := fixture.data
	fixture.data = fixture.data.duplicate(true)
	fixture.data.set_level(Vector2i.ZERO, 4)
	navigation.data = fixture.data
	check(is_equal_approx(navigation._surface_heights(Vector2i.ZERO)[0], 3.0), "Replacing terrain data uses the new resource immediately")
	check(not original_data.changed.is_connected(navigation._clear_surface_cache), "Replacing terrain data disconnects the old invalidator")
	var remaining_connections := fixture.data.changed.get_connections().size() - 1
	navigation = null
	check(fixture.data.changed.get_connections().size() == remaining_connections, "Releasing a path removes its invalidator without keeping it alive")
	local_query.dispose()
	fixture.free()
	wave._finish("cache test", WavePrototype.Outcome.RETREAT)
	world.free()
	await process_frame
	print("Attack surface reuse: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
