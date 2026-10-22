extends SceneTree

const LAYER := preload("res://scripts/rendering/combat_effect_layer.gd")
const LIGHTING := preload("res://scripts/rendering/character_lighting.gd")
const SHADERS := ["light_pierce", "prism_crystal", "mirror_pixels", "ricochet_storm", "ricochet_storm_patch", "fan_slash", "player_sword"]
var checks := 0
var failures := 0
var viewport: SubViewport
var camera: Camera3D
var enemy: WaveEnemy
var sprite: Sprite3D
var effect: MeshInstance3D
var wall: MeshInstance3D
var materials: Array[ShaderMaterial] = []
var references: Array[ShaderMaterial] = []
var camera_config := {}

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func capture() -> Image:
	for frame in 3:
		await physics_frame
		await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func different(first: Image, second: Image) -> int:
	var count := 0
	for y in first.get_height():
		for x in first.get_width():
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.02: count += 1
	return count

func set_view(yaw: float) -> void:
	camera.fov = camera_config.fov
	var pitch := deg_to_rad(float(camera_config.pitch_degrees))
	camera.position = Vector3(0, 0.4, 0) + Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, deg_to_rad(yaw)) * float(camera_config.distance)
	camera.look_at(Vector3(0, 0.4, 0))
	effect.global_basis = camera.global_basis
	effect.global_position = Vector3(0, 0.4, 0) - camera.global_basis.z * 0.8
	wall.global_basis = camera.global_basis
	wall.global_position = Vector3(0, 0.4, 0) + camera.global_basis.z * 0.4
	for node in [camera, effect, wall]: node.reset_physics_interpolation()

func make_materials() -> void:
	var pixels := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.12, 0.45, 0.9, 1.0))
	var texture := ImageTexture.create_from_image(pixels)
	for name in SHADERS:
		var source: Shader = load("res://shaders/combat/" + name + ".gdshader")
		var material := LAYER.material(source)
		var values := {"effect_texture": texture, "slash_texture": texture, "opacity": 0.6,
			"energy": 0.0, "edge_fade": 0.0, "leading_angle": PI, "half_angle": PI,
			"art_scale": Vector2(10, 10), "frame_rect": Vector4(0, 0, 1, 1)}
		if name == "ricochet_storm_patch": values.frame_rect = Vector4(0, 0, 8, 8)
		for uniform in source.get_shader_uniform_list():
			if values.has(uniform.name): LAYER.set_parameter(material, uniform.name, values[uniform.name])
		var reference := material.duplicate() as ShaderMaterial
		reference.next_pass = null
		var reference_shader := Shader.new()
		reference_shader.code = source.code.replace("render_mode ", "render_mode depth_test_disabled, ")
		reference.shader = reference_shader
		materials.append(material)
		references.append(reference)
	var copy := LAYER.duplicate_material(materials[0])
	LAYER.set_parameter(copy, "opacity", 0.1)
	check(materials[0].get_shader_parameter("opacity") == 0.6 and copy.next_pass.get_shader_parameter("opacity") == 0.1, "多刃复制保留独立的淡出与帧参数，不污染其它特效")

func swap_enemy(name: String) -> void:
	if sprite: sprite.free()
	var source: Node = load("res://scenes/enemies/" + name + ".tscn").instantiate()
	sprite = source.get_node("Sprite").duplicate()
	sprite.set("shared_materials", true)
	sprite.set("occlusion_outline_enabled", false)
	enemy.add_child(sprite)
	source.free()

func image_checks() -> void:
	for name in ["slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		swap_enemy(name)
		for yaw in [0.0, 90.0, 180.0]:
			set_view(yaw)
			for index in SHADERS.size():
				effect.material_override = materials[index]
				var actual := await capture()
				if name == "slime" and yaw == 0.0:
					var overlay := materials[index].next_pass
					materials[index].next_pass = null
					var legacy := await capture()
					materials[index].next_pass = overlay
					check(different(actual, legacy) > 0, "关闭修复可重现怪物挡住特效：" + SHADERS[index])
				effect.material_override = references[index]
				var expected := await capture()
				var errors := different(actual, expected)
				check(errors == 0, "技能覆盖实际怪物轮廓且不会重复增亮：%s／%s／镜头 %.0f，误差 %d" % [name, SHADERS[index], yaw, errors])
				if errors > 0 and failures <= 2:
					actual.save_png("D:/.codexfile/work/combat-effect-layer-20261015/actual.png")
					expected.save_png("D:/.codexfile/work/combat-effect-layer-20261015/expected.png")
	set_view(0)
	effect.material_override = materials[2]
	effect.hide()
	wall.show()
	var blocked_base := await capture()
	effect.show()
	var partially_blocked := await capture()
	var wall_errors := 0
	var wall_pixels := 0
	for y in blocked_base.get_height():
		for x in blocked_base.get_width():
			var before := blocked_base.get_pixel(x, y)
			if before.r > 0.7 and before.g < 0.4 and before.b < 0.4:
				wall_pixels += 1
				if before != partially_blocked.get_pixel(x, y): wall_errors += 1
	check(wall_pixels > 20 and wall_errors == 0 and different(blocked_base, partially_blocked) > 0, "局部建筑遮挡仍准确，墙外命中特效保持可见")
	(wall.mesh as QuadMesh).size = Vector2(4, 4)
	effect.hide()
	blocked_base = await capture()
	effect.show()
	check(different(blocked_base, await capture()) == 0, "建筑完全挡住怪物和命中特效时不出现透墙补画")
	wall.hide()
	sprite.hide()
	effect.material_override = materials[2]
	var vanished := await capture()
	effect.material_override = references[2]
	check(different(vanished, await capture()) == 0, "怪物隐藏后不残留上一帧遮罩或重复混色")
	sprite.show()
	sprite.flip_h = true
	sprite.set("lighting_enabled", false)
	effect.material_override = materials[2]
	var unlit := await capture()
	effect.material_override = references[2]
	check(different(unlit, await capture()) == 0, "关闭受光和镜像后的怪物仍保持相同技能层级")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("此测试需要原生渲染以检查真实像素和 stencil")
		quit(2)
		return
	var state := (load("res://scenes/world/world.tscn") as PackedScene).get_state()
	for index in state.get_node_count():
		if not str(state.get_node_path(index)).ends_with("MapEffects/Camera3D"): continue
		for property in state.get_node_property_count(index):
			camera_config[state.get_node_property_name(index, property)] = state.get_node_property_value(index, property)
	check(camera_config.has("fov") and camera_config.has("pitch_degrees") and camera_config.has("distance"), "逐像素检查读取正式地图当前镜头")
	viewport = SubViewport.new()
	viewport.size = Vector2i(320, 200)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	camera = Camera3D.new()
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	viewport.add_child(light)
	enemy = WaveEnemy.new()
	viewport.add_child(enemy)
	effect = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	effect.mesh = quad
	viewport.add_child(effect)
	wall = MeshInstance3D.new()
	var wall_quad := QuadMesh.new()
	wall_quad.size = Vector2(0.4, 3)
	wall.mesh = wall_quad
	var wall_material := StandardMaterial3D.new()
	wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_material.albedo_color = Color(0.9, 0.05, 0.03)
	wall.material_override = wall_material
	viewport.add_child(wall)
	wall.hide()
	make_materials()
	await image_checks()
	viewport.queue_free()
	for frame in 4: await process_frame
	check(LIGHTING._shared_effect_masks.is_empty(), "最后一只怪物退出后释放共用遮罩材质")
	print("Combat effect layers: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
