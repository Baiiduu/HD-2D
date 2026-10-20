extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func properties(node_path: String) -> Dictionary:
	var state: SceneState = (load("res://scenes/world/world.tscn") as PackedScene).get_state()
	for index in state.get_node_count():
		if String(state.get_node_path(index)).trim_prefix("./") != node_path: continue
		var values := {}
		for property in state.get_node_property_count(index):
			values[state.get_node_property_name(index, property)] = state.get_node_property_value(index, property)
		return values
	return {}

func run() -> void:
	var authored := properties("Player/CharacterSpotlight")
	check(authored.has("script"), "World 保存独立的人物重点聚光")
	if not authored.has("script"):
		finish()
		return
	var saved_sprite := properties("Player/Sprite")
	var source := Sprite3D.new()
	source.set_script(saved_sprite.script)
	source.texture = saved_sprite.texture
	source.layers = saved_sprite.layers
	source.occlusion_outline_enabled = false
	var camera_mask: int = properties("MapEffects/Camera3D").cull_mask
	var script: Script = authored.script
	var bit: int = script.RECEIVER_LAYER
	check(source.layers & bit != 0 and source.layers & 1 != 0, "人物保留普通光照图层并加入独立接收层")
	check(camera_mask & bit == 0, "主相机排除仅供照明的图层，防止水中替身重复显示")
	var scene := Node3D.new()
	root.add_child(scene)
	scene.add_child(source)
	var player := Node3D.new()
	scene.add_child(player)
	player.owner = scene
	var camera := Camera3D.new()
	# Reflection.initialize reserves its two mirror view bits on the real camera.
	camera.cull_mask = camera_mask & ~(PlanarWaterReflection.MIRROR_BITS[0] | PlanarWaterReflection.MIRROR_BITS[1])
	scene.add_child(camera)
	camera.rotation_degrees = Vector3(-30, 135, 0)
	var light = script.new()
	light.camera = camera
	player.add_child(light)
	light.owner = scene
	light.set_process(false)
	light.sync_pose()
	check(light.light_cull_mask == bit and light.light_cull_mask & 1 == 0, "补光只直接照人物，不照普通地面、建筑或怪物")
	check(not light.shadow_enabled and light.light_volumetric_fog_energy == 0.0 and light.light_indirect_energy == 0.0 and light.light_specular == 0.0, "补光不增加投影、雾中光柱和地面镜面亮斑")
	check(light.light_bake_mode == Light3D.BAKE_DISABLED and not light.distance_fade_enabled, "动态人物补光不烘焙，也不随镜头距离突然消失")
	var offset: Vector3 = light.global_position - player.global_position
	var aim: Vector3 = player.global_position + Vector3.UP * light.fill_target_height
	check((-light.global_basis.z).dot(light.global_position.direction_to(aim)) > 0.999, "聚光轴准确指向人物身体")
	player.position += Vector3(7.0, 0.3, -5.0)
	light.sync_pose()
	check((light.global_position - player.global_position).is_equal_approx(offset), "人物移动后补光保持相对距离")
	camera.rotation.y += PI * 0.5
	light.sync_pose()
	var rotated: Vector3 = light.global_position - player.global_position
	check(is_equal_approx(rotated.y, offset.y) and Vector2(rotated.x, rotated.z).distance_to(Vector2(offset.z, -offset.x)) < 0.001, "Q/E 方位变化时，人物聚光保持前侧构图")
	light.fill_energy = 0.7
	light.fill_color = Color(1.0, 0.85, 0.7)
	check(is_equal_approx(light.light_energy, 0.7) and light.light_color.is_equal_approx(light.fill_color), "参数直接更新真实灯光")
	light.fill_enabled = false
	check(not light.visible and not light.is_processing(), "关闭补光立即隐藏并停止姿态更新")
	light.fill_enabled = true
	check(light.visible and light.is_processing(), "重新开启复用原灯光")
	light.set_process(false)
	var reflection := PlanarWaterReflection.new()
	scene.add_child(reflection)
	reflection._make_sprite(source, PlanarWaterReflection.MIRROR_BITS[0], -1.0)
	var proxy: MeshInstance3D = reflection.sprites.back().proxy
	check(proxy.layers & light.light_cull_mask != 0 and proxy.layers & camera.cull_mask == 0, "水中人物同步接收补光且不会在主视图重复显示")
	var ordinary := Sprite3D.new()
	ordinary.texture = source.texture
	reflection._make_sprite(ordinary, PlanarWaterReflection.MIRROR_BITS[0], -1.0)
	check(reflection.sprites.back().proxy.layers == PlanarWaterReflection.MIRROR_BITS[0], "普通反射对象和 City 原有图层保持")
	ordinary.free()
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(scene)
	for property in ["fill_enabled", "fill_energy", "fill_color", "fill_height", "fill_front_offset", "fill_side_offset", "fill_angle"]:
		check(entries.any(func(entry): return entry.node == light and entry.property == property and entry.category == "人物" and entry.common and entry.label != property), "人物参数总览提供补光入口：" + property)
	scene.free()
	await process_frame
	finish()

func finish() -> void:
	print("Character spotlight: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
