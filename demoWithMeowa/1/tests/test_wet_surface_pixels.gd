extends SceneTree

var checks := 0
var failures: Array[String] = []
var results := {}

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ", message)

func photo() -> Image:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func difference(first: Image, second: Image) -> int:
	var count := 0
	for y in range(150, first.get_height()):
		for x in range(400, 880):
			var a := first.get_pixel(x,y)
			var b := second.get_pixel(x,y)
			if maxf(absf(a.r-b.r), maxf(absf(a.g-b.g), absf(a.b-b.b))) > 3.0/255.0: count += 1
	return count

func bright_count(image: Image) -> int:
	var count := 0
	for y in range(150, image.get_height()):
		for x in range(400, 880):
			var color := image.get_pixel(x,y)
			if maxf(color.r, maxf(color.g, color.b)) > 0.5: count += 1
	return count

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: wet surface pixel checks need native rendering at 1280x800")
		quit()
		return
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.015,0.02,0.03)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.08,0.08,0.08)
	environment.environment.ambient_light_energy = 0.2
	stage.add_child(environment)
	# Use the production shader and real Terrain bindings, without gameplay or post effects.
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain/terrain.gdshader")
	var color := Image.create_empty(1,1,false,Image.FORMAT_RGBA8)
	color.fill(Color(0.14,0.14,0.14))
	var texture := ImageTexture.create_from_image(color)
	material.set_shader_parameter("city_texture", texture)
	material.set_shader_parameter("wild_texture", texture)
	material.set_shader_parameter("wetness",0.0)
	material.set_shader_parameter("rain_amount",0.0)
	material.set_shader_parameter("stone_relief",0.0)
	material.set_shader_parameter("grass_relief",0.0)
	material.set_shader_parameter("grass_sheen",0.0)
	material.set_shader_parameter("stone_gloss_variation",0.0)
	material.set_shader_parameter("wet_surface_coverage",1.0)
	material.set_shader_parameter("wet_surface_minimum",1.0)
	material.set_shader_parameter("rain_clock",2.0)
	var terrain := Terrain.new()
	terrain.top_material = material
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-6,-6),Vector2i(12,12))
	stage.add_child(terrain)
	var target := Node3D.new()
	stage.add_child(target)
	var camera := FollowCamera.new()
	camera.target = target
	# Read inherited and scene overrides without constructing unrelated gameplay/UI objects.
	var lens_properties := ["fov", "distance", "pitch_degrees", "focus_height", "dof_enabled", "dof_mode",
		"dof_amount", "dof_near_margin", "dof_far_margin", "dof_near_transition", "dof_far_transition"]
	for path in ["res://scenes/shared/map_effects.tscn", "res://scenes/world/world.tscn"]:
		var state: SceneState = (load(path) as PackedScene).get_state()
		for index in state.get_node_count():
			if String(state.get_node_path(index)).trim_prefix("./") not in ["Camera3D", "MapEffects/Camera3D"]: continue
			for item in state.get_node_property_count(index):
				var property := state.get_node_property_name(index,item)
				if property in lens_properties: camera.set(property,state.get_node_property_value(index,item))
	stage.add_child(camera)
	camera.snap_to_target()
	var light := OmniLight3D.new()
	light.position = Vector3(0,2,0)
	light.light_color = Color(1.0,0.7,0.35)
	light.light_energy = 3.0
	light.omni_range = 10.0
	light.light_specular = 1.0
	light.shadow_enabled = true
	stage.add_child(light)
	var before := await photo()
	material.set_shader_parameter("wet_surface_enabled",true)
	var wet := await photo()
	results["wet_difference"] = difference(before,wet)
	check(results.wet_difference > 100, "Wet film changes real native point-light highlights")
	material.set_shader_parameter("ground_directional_reflection_strength",0.0)
	results["local_light_preserved"] = difference(wet,await photo())
	check(results.local_light_preserved <= 10, "Directional reflection control preserves the actual point-light highlight")
	light.light_specular = 0.0
	var diffuse_only := await photo()
	results["specular_difference"] = difference(wet,diffuse_only)
	check(results.specular_difference > 100, "Setting actual light specular to zero removes the wet highlight")
	light.light_specular = 1.0
	material.set_shader_parameter("rain_clock",8.0)
	var moved := await photo()
	results["wave_difference"] = difference(wet,moved)
	check(results.wave_difference > 30, "Advancing the shared surface clock moves the reflected highlight")
	material.set_shader_parameter("wet_surface_ripple_speed",0.0)
	var still := await photo()
	material.set_shader_parameter("rain_clock",12.0)
	results["stopped_wave_difference"] = difference(still,await photo())
	check(results.stopped_wave_difference <= 10, "Zero ripple speed stops fair-weather wave motion")
	light.visible = false
	results["light_off_bright_pixels"] = bright_count(await photo())
	check(results.light_off_bright_pixels == 0, "Turning the real point light off leaves no painted luminous reflection")
	light.visible = true
	light.light_color = Color(0.25,0.45,1.0)
	var blue := await photo()
	check(difference(still,blue) > 100, "The wet highlight follows actual point-light colour")
	light.light_color = Color(1.0,0.7,0.35)
	# The occluder is invisible to the main view and only casts a physical shadow.
	var blocker := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12,0.1,12)
	blocker.mesh = box
	blocker.position.y = 0.8
	blocker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	stage.add_child(blocker)
	results["shadow_bright_pixels"] = bright_count(await photo())
	check(results.shadow_bright_pixels < bright_count(still) * 0.1, "A real shadow caster blocks the wet point-light reflection")
	blocker.free()
	# A directional light illuminates the same wet surface without a specular band.
	light.visible = false
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-camera.pitch_degrees,180,0)
	sun.light_energy = 3.0
	stage.add_child(sun)
	material.set_shader_parameter("ground_directional_reflection_strength",1.0)
	var solar := await photo()
	material.set_shader_parameter("ground_directional_reflection_strength",0.0)
	var solar_diffuse := await photo()
	results["directional_removed"] = difference(solar,solar_diffuse)
	check(results.directional_removed > 100, "Only the directional wet-surface highlight is removed")
	sun.visible = false
	check(difference(solar_diffuse,await photo()) > 100, "Directional diffuse illumination remains active")
	sun.free()
	light.visible = true
	material.set_shader_parameter("wet_surface_coverage",0.0)
	material.set_shader_parameter("wet_surface_enabled",false)
	var disabled := await photo()
	material.set_shader_parameter("wet_surface_enabled",true)
	check(difference(disabled,await photo()) <= 10, "Zero wet coverage reproduces the original material response")
	terrain.data.biomes.fill(TerrainData.Biome.WILD)
	terrain.data.emit_changed()
	material.set_shader_parameter("wet_surface_coverage",1.0)
	material.set_shader_parameter("wet_surface_grass_response",0.0)
	material.set_shader_parameter("wet_surface_enabled",false)
	var grass := await photo()
	material.set_shader_parameter("wet_surface_enabled",true)
	check(difference(grass,await photo()) <= 10, "Grass can retain its original response independently of reflective paving")
	# The real water shader remains reflective even when ground solar glare is off.
	terrain._generated.hide()
	light.visible = false
	var water := MeshInstance3D.new()
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(12,12)
	water.mesh = water_mesh
	water.position.y = 0.02
	var water_material := ShaderMaterial.new()
	water_material.shader = load("res://shaders/water/water.gdshader")
	# Freeze TIME-driven ripples/foam so this comparison isolates the ground control.
	water_material.set_shader_parameter("flow",Vector2.ZERO)
	water_material.set_shader_parameter("wave_strength",0.0)
	water_material.set_shader_parameter("foam_strength",0.0)
	water.material_override = water_material
	stage.add_child(water)
	var water_sun := DirectionalLight3D.new()
	water_sun.rotation_degrees = Vector3(-camera.pitch_degrees,180,0)
	water_sun.light_energy = 3.0
	stage.add_child(water_sun)
	material.set_shader_parameter("ground_directional_reflection_strength",0.0)
	var water_lit := await photo()
	material.set_shader_parameter("ground_directional_reflection_strength",1.0)
	results["water_ground_control_difference"] = difference(water_lit,await photo())
	check(results.water_ground_control_difference <= 10, "Ground directional control does not alter real water reflections")
	water_material.set_shader_parameter("highlight_strength",0.0)
	results["real_water_reflection"] = difference(water_lit,await photo())
	check(results.real_water_reflection > 100, "The original water shader still reflects the actual directional light")
	print("Wet surface pixels: ", checks, " checks; ", failures.size(), " failures; ", JSON.stringify(results))
	stage.free()
	for frame in 3: await process_frame
	quit(0 if failures.is_empty() else 1)
