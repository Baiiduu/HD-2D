extends SceneTree

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func settle() -> void:
	for frame in 5:
		await process_frame

func run() -> void:
	# Reuse the formal terrain data and common effects independently of UI/save state.
	var scene := Node3D.new()
	var terrain := Terrain.new()
	terrain.name = "Homestead"
	terrain.data = load("res://data/spawn_terrain.tres").duplicate(true)
	scene.add_child(terrain)
	var player := Node3D.new()
	player.name = "Player"
	scene.add_child(player)
	var effects: MapEffects = load("res://scenes/shared/map_effects.tscn").instantiate()
	effects.terrain = terrain
	effects.player = player
	scene.add_child(effects)
	root.add_child(scene)
	current_scene = scene
	await settle()
	var atmosphere := scene.get_node("MapEffects/AtmosphericLight")
	var art := scene.get_node("MapEffects/ArtDirection") as ArtDirection
	var camera := scene.get_node("MapEffects/Camera3D") as FollowCamera
	atmosphere.set_process(false)
	assert(atmosphere.map_accents_enabled and atmosphere.follow_global_direction)
	assert(atmosphere._accent_targets.size() > 12)
	assert(atmosphere._rays.size() == 6)
	assert(not atmosphere.has_node("MapLight") and not atmosphere.has_node("MapCloud"))
	var main_energy := art.moon.light_energy
	var main_color := art.moon.light_color
	var rect := terrain.get_world_rect()
	for target: Vector3 in atmosphere._accent_targets:
		assert(rect.has_point(Vector2(target.x, target.z)))
		var cell := terrain.data.world_to_cell(target - terrain.global_position)
		assert(is_equal_approx(target.y, terrain.global_position.y + terrain.data.get_level(cell) * terrain.data.layer_height))
	for point in [Vector2(-12, 6), Vector2(13, 8), Vector2(-8, -18), Vector2(-6, 16)]:
		player.global_position = Vector3(point.x, 1.0, point.y)
		for frame in 40:
			atmosphere._update_map_accents(0.1)
		var active := 0
		var assigned: Array[int] = []
		for i in atmosphere._rays.size():
			var ray: SpotLight3D = atmosphere._rays[i]
			if ray.visible:
				active += 1
				var index: int = atmosphere._accent_slots[i]
				assert(index not in assigned)
				assigned.append(index)
				assert(atmosphere._accent_distance(index, player.global_position) < atmosphere.accent_radius)
				assert((-ray.global_basis.z).dot(-art.moon.global_basis.z) > 0.999)
				assert(ray.light_volumetric_fog_energy == 0.0 and ray.light_projector != null)
		assert(active > 0 and active <= atmosphere.max_active_accents)
	# Camera rotation changes neither placement nor selection.
	var positions := PackedVector3Array()
	for ray: SpotLight3D in atmosphere._rays: positions.append(ray.global_position)
	camera.yaw_degrees = 90.0
	camera.snap_to_target()
	atmosphere._update_map_accents(0.1)
	for i in atmosphere._rays.size(): assert(atmosphere._rays[i].global_position.is_equal_approx(positions[i]))
	# Leaving an area fades the old lights before slots can move to new targets.
	var energies := PackedFloat32Array()
	for ray: SpotLight3D in atmosphere._rays: energies.append(ray.light_energy)
	player.global_position = Vector3(15, 0, -20)
	atmosphere._update_map_accents(0.02)
	for i in atmosphere._rays.size():
		assert(absf(atmosphere._rays[i].light_energy - energies[i]) <= atmosphere.surface_energy * 0.02 / atmosphere.accent_fade_time + 0.001)
	# Shared direction follows live main-light changes, including the existing daylight controller.
	art.moon.rotation_degrees = Vector3(-60, 35, 0)
	atmosphere._process(0.1)
	for ray: SpotLight3D in atmosphere._rays:
		if ray.visible: assert((-ray.global_basis.z).dot(-art.moon.global_basis.z) > 0.999)
	atmosphere.surface_energy = 0.0
	atmosphere.shadows_enabled = false
	await settle()
	for ray: SpotLight3D in atmosphere._rays: assert(not ray.visible and not ray.shadow_enabled)
	assert(art.moon.light_energy == main_energy and art.moon.light_color == main_color)
	atmosphere.surface_energy = 2.2
	atmosphere.shadows_enabled = true
	atmosphere.max_active_accents = 3
	await settle()
	assert(atmosphere._rays.size() == 3)
	# Terrain edits rebuild fixed targets without writing the original map resource.
	var old_count: int = atmosphere._accent_targets.size()
	terrain.data.resize(Vector2i(-20, -22), Vector2i(40, 44))
	await settle()
	assert(atmosphere._accent_targets.size() > old_count)
	var target: Vector3 = atmosphere._accent_targets[0]
	terrain.data.set_level(terrain.data.world_to_cell(target), 4)
	await settle()
	assert(is_equal_approx(atmosphere._accent_targets[0].y, 4.0 * terrain.data.layer_height))
	atmosphere.map_accents_enabled = false
	await settle()
	assert(atmosphere._rays.size() == 3)
	for i in 3:
		var ray: SpotLight3D = atmosphere._rays[i]
		assert(ray.visible and is_equal_approx(ray.light_energy, 2.2))
		var target_position: Vector3 = atmosphere.global_position + Vector3.RIGHT * (i - 1) * atmosphere.spacing
		assert(ray.global_position.distance_to(target_position - atmosphere._surface_direction * (atmosphere.source_height / -atmosphere._surface_direction.y)) < 0.01)
	atmosphere.map_accents_enabled = true
	await settle()
	var child_count: int = atmosphere.get_child_count()
	for repeat in 5: atmosphere.apply_atmosphere()
	await settle()
	assert(atmosphere.get_child_count() == child_count)
	assert(atmosphere._distant_rays.size() == 3 and atmosphere._beams.size() == 3)
	print("PASS: fixed terrain-aware accents across map, bounded light count, smooth transitions, global direction, QE, zero/shadow controls, resize and original local mode")
	scene.queue_free()
	await settle()
	quit()
