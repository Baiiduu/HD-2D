extends SceneTree

const OUT := "D:/.codexfile/work/surface-integration/"
var viewport: SubViewport
var sprite: Sprite3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); print("FAIL: ",label)

func shot(enabled: bool,flip := false,debug := true) -> Image:
	sprite.set("normal_mapping_enabled",enabled)
	sprite.flip_h = flip
	sprite.call("apply_lighting")
	sprite.get("_material").set_shader_parameter("normal_debug",debug)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func same_alpha(a: Image,b: Image) -> bool:
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x,y).a != b.get_pixel(x,y).a: return false
	return true

func changed_pixels(a: Image,b: Image) -> int:
	var count := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x,y).a > 0.5 and (a.get_pixel(x,y)-b.get_pixel(x,y)).r != 0.0: count += 1
	return count

func run() -> void:
	AudioServer.set_bus_mute(0,true)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(384,384)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.4,0.5,0.7)
	environment.environment.ambient_light_energy = 0.3
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.0
	camera.position = Vector3(0,0,3)
	camera.current = true
	viewport.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-55,0)
	sun.light_color = Color(1.0,0.85,0.7)
	sun.light_energy = 1.4
	viewport.add_child(sun)
	sprite = load("res://scripts/rendering/character_lighting.gd").new()
	sprite.pixel_size = 0.0234375
	sprite.set("occlusion_outline_enabled",false)
	viewport.add_child(sprite)
	sprite.call("apply_lighting")
	var shader := Shader.new()
	var code := FileAccess.get_file_as_string("res://shaders/character/character_lighting.gdshader").replace("\r\n","\n")
	code = code.replace("uniform vec4 tint", "uniform bool normal_debug = false;\nuniform vec4 tint")
	code = code.replace("\n}\n\nvoid light()", "\nif (normal_debug) EMISSION = NORMAL * 0.5 + 0.5;\nif (normal_debug) ALBEDO = vec3(0.0);\n}\n\nvoid light()")
	shader.code = code
	sprite.get("_material").shader = shader
	for path in ["res://assets/meowa/player/idle_00.png","res://assets/meowa/player/run_03.png","res://assets/meowa/player/idle_back_00.png","res://assets/meowa/player/dodge/dodge_04.png"]:
		sprite.texture = load(path)
		var original := await shot(false)
		var detail := await shot(true)
		check(same_alpha(original,detail),path.get_file()+" preserves every silhouette pixel")
		check(changed_pixels(original,detail) > 10,path.get_file()+" renders a non-flat normal")
		var lit_before := await shot(false,false,false)
		var lit_after := await shot(true,false,false)
		check(changed_pixels(lit_before,lit_after) > 5,path.get_file()+" responds to real directional light")
		var flipped := await shot(true,true)
		check(changed_pixels(flipped,detail) > 10,path.get_file()+" flip renders")
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/meowa/player/dodge/sheet.png")
	for index in [0,3,4,7]:
		atlas = AtlasTexture.new()
		atlas.atlas = load("res://assets/meowa/player/dodge/sheet.png")
		atlas.region = Rect2((index%4)*128,floori(index/4.0)*96,128,96)
		sprite.texture = atlas
		sprite.call("_sync_texture")
		var original := await shot(false)
		var detail := await shot(true)
		detail.save_png(OUT+"atlas-all-%d.png" % index)
		print("Frame ",index," region ",atlas.region," normal region ",sprite.get("_material").get_shader_parameter("sprite_region"))
		check(same_alpha(original,detail),"Atlas frame %d keeps exact alpha" % index)
		check(changed_pixels(original,detail)>10,"Atlas frame %d has matching frame-local relief" % index)
		var single: Texture2D = load("res://assets/meowa/player/dodge/dodge_%02d.png" % index)
		sprite.texture = single
		var separate := await shot(true)
		if detail.get_data() != separate.get_data():
			detail.save_png(OUT+"atlas-%d.png" % index)
			separate.save_png(OUT+"separate-%d.png" % index)
		check(detail.get_data() == separate.get_data(),"Atlas frame %d equals its separate PNG without cross-frame sampling" % index)
		# Reflection proxies use a frame-local quad instead of Sprite3D atlas UVs.
		sprite.texture = atlas
		sprite.flip_h = false
		sprite.call("apply_lighting")
		var reflected := ShaderMaterial.new()
		reflected.shader = shader
		sprite.call("apply_lighting_to",reflected,true)
		reflected.set_shader_parameter("normal_debug",true)
		var quad := MeshInstance3D.new()
		quad.mesh = QuadMesh.new()
		quad.mesh.size = atlas.get_size() * sprite.pixel_size
		quad.material_override = reflected
		viewport.add_child(quad)
		sprite.visible = false
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var mirror := viewport.get_texture().get_image()
		mirror.save_png(OUT+"mirror-%d.png" % index)
		check(detail.get_data() == mirror.get_data(),"Atlas frame %d reflection keeps the same normal and alpha" % index)
		sprite.visible = true
		quad.visible = false
		var flipped := await shot(true,true)
		sprite.call("apply_lighting_to",reflected,true)
		reflected.set_shader_parameter("normal_debug",true)
		sprite.visible = false
		quad.visible = true
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		check(flipped.get_data() == viewport.get_texture().get_image().get_data(),"Atlas frame %d reflection preserves horizontal flip normals" % index)
		quad.queue_free()
		sprite.visible = true
	viewport.queue_free()
	for frame in 3: await process_frame
	print(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
