extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain
var player: Player
var wave: WavePrototype

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func settle(count := 8) -> void:
	for frame in count: await physics_frame

func place(point: Vector3) -> void:
	player.body_ricochet.cancel(true)
	player.global_position = point
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await settle()
	player.set_physics_process(false)
	player.sword.set_physics_process(false)

func bounce_at_water(point: Vector3, heading: Vector3, label: String) -> void:
	await place(point)
	var body := player.body_ricochet
	var audio := world.get_node("MapEffects/GameAudio") as GameAudio
	audio.stop_all()
	var surfaces: Array[bool] = []
	var on_bounce := func(hit): surfaces.append(terrain.is_reflective_water_shape(hit.get_collider(), hit.get_collider_shape_index()))
	body.surface_bounced.connect(on_bounce)
	check(body.begin_charge(heading), "水域边界用例正常蓄力：" + label)
	body.advance(0.8, Vector3.ZERO, false)
	var predicted := AimPathData.new()
	body.predict_path(BodyPathPrediction.new(), predicted, 8.0, 1, 0.0)
	check(body.release_charge(), "水域边界用例正常发射：" + label)
	var stayed_dry := true
	for frame in 120:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		stayed_dry = stayed_dry and not terrain.data.has_overlay(terrain.data.world_to_cell(player.global_position), TerrainData.OVERLAY_WATER)
		if body.bounce_count > 0 or not body.flying: break
	check(body.bounce_count >= 1 and not surfaces.is_empty() and surfaces[0] and stayed_dry, "直接在既有水域边界反弹，未进入水格：" + label)
	check(not predicted.contacts.is_empty() and not predicted.segments.is_empty() and TerrainPath.horizontal_distance(predicted.segments[0].end, player.global_position) < 0.08, "水域边界首碰预览与真实胶囊同源：" + label)
	check(audio._voices.any(func(slot): return slot.active and slot.cue == &"core:bounce_stone"), "水域边界复用当前反弹声：" + label)
	body.surface_bounced.disconnect(on_bounce)
	body.cancel(true)

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var surface_hash := FileAccess.get_sha256("res://data/world/world_surface.tres")
	var data_hash := FileAccess.get_sha256("res://data/world/world_terrain.tres")
	var saved_paints := (load("res://data/world/world_terrain.tres") as TerrainData).paints.duplicate()
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/GameAudio").load_local_mix = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	wave = world.get_node("WavePrototype")
	wave.population_rules = wave.population_rules.duplicate()
	wave.population_rules.simulation_mode = false
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave.set_physics_process(false)
	terrain = world.get_node("Homestead")
	player = world.get_node("Player")
	player.set_physics_process(false)
	player.ricochet_rules = player.ricochet_rules.duplicate()
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.sword.rules = player.sword.rules.duplicate()
	player.sword.rules.enabled = false
	var data := terrain.data
	check(data.origin == Vector2i(-10, 18) and data.size == Vector2i(21, 21), "战区范围与地形格尺寸保持")
	check(ResourceLoader.get_resource_uid(data.resource_path) == ResourceUID.text_to_id("uid://cn4m5amkrc58p"), "原有地形 UID 保留")
	var wet := 0
	var unchanged := true
	for z in range(data.origin.y, data.origin.y + data.size.y):
		for x in range(data.origin.x, data.origin.x + data.size.x):
			var cell := Vector2i(x, z)
			var expected := x >= 6 and x <= 9 and z >= 19 and z <= 21 and cell != Vector2i(6, 21)
			if data.has_overlay(cell, TerrainData.OVERLAY_WATER): wet += 1
			unchanged = unchanged and data.has_overlay(cell, TerrainData.OVERLAY_WATER) == expected
			unchanged = unchanged and data.get_level(cell) == (-1 if expected else 0)
	check(wet == 11 and unchanged and data.paints == saved_paints, "仅东北角十一格下沉，原有画笔编号保留")
	check(not data.has_overlay(Vector2i(6, 21), TerrainData.OVERLAY_WATER), "保留朝向战场的缺角落脚地")
	var water := terrain._generated.get_node_or_null("Water") as MeshInstance3D
	check(water != null and water.material_override == terrain.water_material, "生成真实水面并绑定预览水材质")
	check(water != null and water.layers & Terrain.WATER_LIGHT_LAYER != 0, "水面接收路灯独立水光")
	if water: check(is_equal_approx(water.get_aabb().position.y, -0.32), "水面位于岸下零点三二米")
	check(not terrain._generated.has_node("Bridges") and not terrain._generated.has_node("Waterfalls"), "第一版只接入水面，桥与落水后续细化")
	check((terrain.water_material as ShaderMaterial).shader.resource_path == "res://shaders/water/water.gdshader", "复用原有水波与岸边泡沫着色器")
	var lamp := world.get_node("WorldDetails/WaterGarden/ShoreLamp") as PlazaStreetlamp
	check(lamp != null and lamp._heads.size() == 2 and lamp.collision_enabled, "接入带真实碰撞的现有双头路灯")
	check(not data.has_overlay(data.world_to_cell(lamp.global_position), TerrainData.OVERLAY_WATER), "路灯底座位于岸上")
	check(not world.get_node("WorldDetails/WaterGarden").has_node("Banks") and terrain.water_boundary_reflection_enabled, "直接启用水域边界反弹，不增加石沿模型")
	var marked_shapes := 0
	for shape in terrain._water_collision_body.get_children():
		if shape.get_meta(&"water_boundary", false): marked_shapes += 1
	check(marked_shapes == wet and terrain._collision_body.get_child_count() == 1 and terrain.ground_collision_body() != null, "水域阻挡形状保持原样并与陆地支撑分离")
	for head in lamp._heads:
		check(head.get_node("WaterLight").light_energy > 0.0 and head.get_node("WaterLight").light_cull_mask == Terrain.WATER_LIGHT_LAYER, "双灯头各自保留真实水面照明")
	var mirror := world.get_node("MapEffects/WaterReflection") as PlanarWaterReflection
	check(mirror.views.size() == 1 and mirror.water == terrain.water_material, "单一水位只创建一张既有平面反射视图")
	check(mirror.sprites.any(func(item): return item.source == player.sprite), "人物使用现有实际帧倒影代理")
	var navigation := TerrainPath.new()
	navigation.build(terrain, 0.32, [player.get_rid()])
	var no_water_points := true
	for id in navigation.graph.get_point_ids():
		var point := navigation.graph.get_point_position(id)
		if data.has_overlay(data.world_to_cell(terrain.to_local(point)), TerrainData.OVERLAY_WATER): no_water_points = false
	check(no_water_points and navigation.graph.get_point_count() > 0, "真实导航排除池水并保留陆地路线")
	check(not navigation.can_walk_direct(Vector3(8, 0, 32), Vector3(12.8, 0, 32)), "怪物不能直线穿池")
	var route := navigation.route(Vector3(8, 0, 32), Vector3(12.8, 0, 36))
	check(route.size() > 1, "池岸两侧仍有真实绕行路线")
	var definition := load("res://data/enemies/wave_slime.tres") as WaveEnemyDefinition
	var spawn_safe := true
	for x in range(6, 10):
		var point := Vector3(x * data.cell_size, 0, 32)
		spawn_safe = spawn_safe and not wave._valid_spawn(point, definition, player.global_position)
	check(spawn_safe, "普通出怪资格拒绝池内位置")
	await place(Vector3(8, 0.03, 32))
	var hit := player.move_and_collide(Vector3.RIGHT * 4.0)
	check(hit != null and terrain.is_reflective_water_shape(hit.get_collider(), hit.get_collider_shape_index()) and player.global_position.x < 8.8, "人物真实胶囊被既有水域边界阻挡，不能走入水域")
	var lamp_body := lamp._generated.get_node("LampCollision") as StaticBody3D
	# 隔离可编辑的灯位，检查水域边界；随后恢复并单独验证路灯碰撞。
	player.add_collision_exception_with(lamp_body)
	for sample in [
		[Vector3(8, 0.03, 31.2), Vector3.RIGHT, "西岸"],
		[Vector3(12.8, 0.03, 35.4), Vector3.FORWARD, "南岸"],
		[Vector3(9.6, 0.03, 33.6), Vector3.FORWARD, "缺角北沿"],
		[Vector3(9.2, 0.03, 33.6), Vector3.RIGHT, "缺角东沿"],
		[Vector3(12.8, 0.03, 29.2), Vector3.BACK, "北岸"],
		[Vector3(15.6, 0.03, 32), Vector3.LEFT, "东岸"],
		[Vector3(8, 0.03, 31.8), Vector3(1, 0, -0.4).normalized(), "斜撞西岸"]]:
		await bounce_at_water(sample[0], sample[1], sample[2])
	player.remove_collision_exception_with(lamp_body)
	terrain.water_boundary_reflection_enabled = false
	await place(Vector3(8, 0.03, 32))
	var body := player.body_ricochet
	check(body.begin_charge(Vector3.RIGHT), "关闭边界反弹后仍能正常蓄力")
	body.advance(0.8, Vector3.ZERO, false)
	check(body.release_charge(), "关闭边界反弹后仍能正常发射")
	for frame in 120:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		if not body.flying: break
	check(not body.flying and body.bounce_count == 0 and player.global_position.x < 8.8, "独立关闭后恢复遇水终止，其他场景默认规则保持")
	terrain.water_boundary_reflection_enabled = true
	await place(lamp.global_position + Vector3.LEFT * 2.0 + Vector3.UP * 0.03)
	check(body.begin_charge(Vector3.RIGHT), "路灯碰撞用例正常蓄力")
	body.advance(0.8, Vector3.ZERO, false)
	check(body.release_charge(), "路灯碰撞用例正常发射")
	for frame in 90:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		if body.bounce_count > 0 or not body.flying: break
	check(body.bounce_count == 1 and body.direction.x < 0.0, "岸边路灯沿既有胶囊碰撞反弹")
	body.cancel(true)
	var snapshot := data.to_image().get_data()
	var visual := world.get_node("VisualSample") as SpawnVisualSample
	var camera: FollowCamera = world.get_node("MapEffects").get_map_camera()
	var camera_values := [camera.fov, camera.distance, camera.pitch_degrees, camera.yaw_degrees]
	for style in 4:
		visual.style = style
		visual.apply_style()
		await process_frame
		check(data.to_image().get_data() == snapshot and lamp.light_enabled and mirror.water == terrain.water_material and terrain.water_boundary_reflection_enabled, "Style 保留水域、直接反弹与路灯：%d" % style)
	check(camera_values == [camera.fov, camera.distance, camera.pitch_degrees, camera.yaw_degrees], "水景及 Style 不改正式相机")
	check(surface_hash == FileAccess.get_sha256("res://data/world/world_surface.tres") and data_hash == FileAccess.get_sha256("res://data/world/world_terrain.tres"), "运行和风格切换不改写手绘存档或地形资源")
	world.queue_free()
	await settle()
	print("Battle corner water: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
