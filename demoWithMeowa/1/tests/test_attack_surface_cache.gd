extends SceneTree

var checks := 0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	assert(value, label)

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
	check(wave.start_run(), "Real battle starts")
	wave._spawn_queue.clear()
	check(wave._spawn_enemy(), "A living target keeps the battle active")
	var enemy: WaveEnemy = wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.health = 10000
	player.global_position = world.get_node("BattleArea").global_position + Vector3.UP * 0.03
	enemy.global_position = player.global_position + Vector3.FORWARD * 1.5
	fan.audio_enabled = false
	fan.knockback_distance = 0
	check(fan.apply_skill_level(7), "Dual rotation is available")
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
	var query := wave.get_attack_surface_query()
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
	fan._locked_basis = Basis.IDENTITY
	fan._update_mesh(origin)
	var clipped: PackedVector3Array = fan._mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var reach := 0.0
	for vertex in clipped: reach = maxf(reach, -vertex.z)
	check(reach < 0.8 and fan._mesh.mesh != mesh, "Fallback geometry stops at the wall")
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
	fixture.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_RAMP, true)
	check(not local_query.unclipped_flat(fixture.global_position + Vector3.UP * 0.4, 1.0), "A ramp never reuses a flat mesh")
	local_query.dispose()
	fixture.free()
	wave._finish("cache test", WavePrototype.Outcome.RETREAT)
	world.free()
	await process_frame
	print("PASS: %d attack surface and mesh reuse checks" % checks)
	quit()
