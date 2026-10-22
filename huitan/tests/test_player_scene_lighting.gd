extends SceneTree

const LIGHTING := preload("res://scripts/rendering/character_lighting.gd")
const PARAMETERS := ["lighting_enabled", "light_wrap", "top_light_response", "back_rim_strength", "local_light_response", "normal_mapping_enabled", "normal_mapping_strength"]
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func scene_properties(path: String, node_path := "Player/Sprite") -> Dictionary:
	var state: SceneState = (load(path) as PackedScene).get_state()
	for index in state.get_node_count():
		if String(state.get_node_path(index)).trim_prefix("./") != node_path: continue
		var result := {}
		for property in state.get_node_property_count(index):
			result[state.get_node_property_name(index, property)] = state.get_node_property_value(index, property)
		return result
	return {}

func subject(texture: Texture2D) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.set_script(LIGHTING)
	sprite.texture = texture
	sprite.shaded = true
	sprite.set("shared_materials", true)
	sprite.set("normal_mapping_enabled", true)
	return sprite

func animation_textures() -> Array[Texture2D]:
	var unique := {}
	for suffix in ["movement", "attack", "flight"]:
		var frames: SpriteFrames = load("res://data/combat/scenes/world/player/character_%s.tres" % suffix)
		for animation in frames.get_animation_names():
			for index in frames.get_frame_count(animation):
				var texture := frames.get_frame_texture(animation, index)
				unique[texture.resource_path] = texture
	var result: Array[Texture2D] = []
	result.assign(unique.values())
	return result

func check_normal_data(texture: Texture2D, normal: Texture2D, manifest: Dictionary) -> void:
	var color := texture.get_image()
	var data := normal.get_image()
	check(color.get_size() == data.get_size(), "法线与原帧保持同尺寸：" + texture.resource_path)
	if color.get_size() != data.get_size(): return
	var alpha_matches := true
	var normalized := true
	var nonflat := 0
	for y in color.get_height():
		for x in color.get_width():
			var sample := data.get_pixel(x, y)
			if not is_equal_approx(sample.a, color.get_pixel(x, y).a): alpha_matches = false
			var vector := Vector3(sample.r, sample.g, sample.b) * 2.0 - Vector3.ONE
			if absf(vector.length() - 1.0) > 0.015: normalized = false
			if sample.a > 0.5 and Vector2(vector.x, vector.y).length() > 0.04: nonflat += 1
	check(alpha_matches and normalized and nonflat > 10, "法线保留逐像素透明度并提供有限体积起伏：" + texture.resource_path)
	check(manifest[texture.resource_path].source_sha256 == FileAccess.get_sha256(texture.resource_path), "法线对应当前原始动画，不改写人物颜色图：" + texture.resource_path)
	var imported := ConfigFile.new()
	check(imported.load(normal.resource_path + ".import") == OK and imported.get_value("params", "compress/mode") == 0 and imported.get_value("params", "detect_3d/compress_to") == 0 and not imported.get_value("params", "mipmaps/generate"), "人物法线无损导入并保留原像素采样：" + texture.resource_path)

func run() -> void:
	var model := LIGHTING.new()
	if model.get("local_light_response") == null:
		check(false, "人物需要独立调节真实路灯和点光响应，不修改场景灯光")
		model.free()
		quit(1)
		return
	check(is_equal_approx(model.get("local_light_response"), 1.0), "共享材质默认保持原有真实局部光强度")
	model.free()
	var world := scene_properties("res://scenes/world/world.tscn")
	var moon := scene_properties("res://scenes/shared/map_effects.tscn", "Moon")
	var environment: Environment = scene_properties("res://scenes/world/world.tscn", "MapEffects/WorldEnvironment").environment
	check(environment.ssao_enabled and environment.ssil_enabled and environment.ssr_enabled, "World 环境已开启原生 SSAO、SSIL 和湿地面 SSR")
	check(is_equal_approx(world.get("local_light_response", 1.0), 1.25), "World 独立开启温和的主角路灯响应，不抬高全场照明")
	check(not world.get("character_fill_enabled", false), "World 只用场景真实光照，不开启常亮自发光补光")
	check(world.get("shaded", false) and world.get("normal_mapping_enabled", false) and world.get("alpha_cut") == SpriteBase3D.ALPHA_CUT_DISCARD, "人物使用真实受光与透明裁切阴影通路")
	check(moon.get("shadow_enabled", false) and (int(moon.get("light_cull_mask", 1)) & int(world.get("layers", 1))) != 0, "现有主光开启阴影并覆盖人物图层")
	var holder := Node3D.new()
	root.add_child(holder)
	var first := subject(world.texture)
	var second := subject(world.texture)
	holder.add_child(first)
	holder.add_child(second)
	first.owner = holder
	first.pixel_size = world.pixel_size
	first.transform = world.transform
	var pose := first.transform
	var pixel := first.pixel_size
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(holder)
	check(not first.get_property_list().any(func(info): return info.name.begins_with("character_fill_") or info.name.begins_with("character_rim_")), "人物不再提供误导的独立常亮补光参数")
	for property in PARAMETERS:
		check(entries.any(func(item): return item.property == property and item.node == first and item.category == "人物" and item.common and item.label != property), "参数总览提供实际受光入口：" + property)
	first.apply_lighting()
	second.apply_lighting()
	var original: ShaderMaterial = second.material_override
	check(first.material_override == original, "相同帧与受光参数继续共享材质")
	first.set("light_wrap", 0.15)
	first.set("normal_mapping_strength", 0.55)
	first.set("local_light_response", 1.6)
	first.flip_h = true
	first.apply_lighting()
	check(first.material_override != original and not original.get_shader_parameter("flip_h"), "个人受光与翻转参数不串到其它角色")
	check(is_equal_approx(first.material_override.get_shader_parameter("local_light_response"), 1.6) and is_equal_approx(original.get_shader_parameter("local_light_response"), 1.0), "路灯响应只作用于当前人物，不串到共享材质的其它角色")
	var mirror := ShaderMaterial.new()
	mirror.shader = LIGHTING.SHADER
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SurfaceNormalMaps.MANIFEST))
	var missing: Array[String] = []
	var textures := animation_textures()
	for texture in textures:
		var normal := SurfaceNormalMaps.for_texture(texture)
		if not normal:
			missing.append(texture.resource_path)
			continue
		check_normal_data(texture, normal, manifest)
		first.texture = texture
		first.apply_lighting_to(mirror, true)
		var material: ShaderMaterial = first.material_override
		check(material.get_shader_parameter("normal_mapping_enabled") and material.get_shader_parameter("normal_texture") == normal, "切换动画帧即时绑定对应场景受光法线：" + texture.resource_path)
		check(mirror.get_shader_parameter("normal_texture") == normal and mirror.get_shader_parameter("mirror_view") and mirror.get_shader_parameter("flip_h"), "倒影与翻转保持同一帧真实受光：" + texture.resource_path)
	check(not textures.is_empty() and missing.is_empty(), "待机、行走、普攻、弹射的全部动画帧都有对应法线；缺失 %d 帧" % missing.size())
	first.apply_lighting_to(mirror, true)
	for property in PARAMETERS:
		check(mirror.get_shader_parameter(property) == first.material_override.get_shader_parameter(property), "水面倒影同步受光参数：" + property)
	check(first.texture in textures or not missing.is_empty(), "材质沿用当前动作原帧")
	check(first.pixel_size == pixel and first.transform == pose, "受光接入保持原像素密度与脚底锚点")
	first.set("local_light_response", 0.0)
	first.apply_lighting()
	first.apply_lighting_to(mirror, true)
	check(is_zero_approx(first.material_override.get_shader_parameter("local_light_response")) and is_zero_approx(mirror.get_shader_parameter("local_light_response")), "局部光响应可设为零，人物与倒影同步且不被默认值覆盖")
	holder.free()
	await process_frame
	print("Player scene lighting: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
