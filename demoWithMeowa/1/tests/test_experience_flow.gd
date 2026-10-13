extends SceneTree

var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func run() -> void:
	var model := RunGrowthState.new()
	model.rules = ExperienceRules.new()
	model.add_experience(6)
	var hud: ExperienceHUD = load("res://scenes/ui/experience_hud.tscn").instantiate()
	root.add_child(hud)
	hud.set_process(false)
	hud.bind_state(model)
	var fill_size := hud._fill.size
	var clip_size := hud._clip.size
	var shader := hud._fill.material as ShaderMaterial
	hud._process(hud.flow_duration * 0.25)
	var first: float = shader.get_shader_parameter("sweep_position")
	hud._process(hud.flow_duration * 0.25)
	check(shader.get_shader_parameter("sweep_position") > first and shader.get_shader_parameter("sweep_strength") > 0.0, "Flow moves across the earned portion of the strip")
	check(is_equal_approx(shader.get_shader_parameter("visible_fraction"), 0.6), "Sweep knows the actual clipped experience fraction")
	check(model.experience == 6 and model.level == 1 and model.pending_choices == 0 and hud._fill.size == fill_size and hud._clip.size == clip_size, "Animation cannot change XP, level, selection queue or bar layout")
	hud.flow_enabled = false
	hud._process(0.01)
	check(shader.get_shader_parameter("sweep_strength") == 0.0, "Flow can be disabled independently")
	# 旧的已打开场景没有新材质；编辑器刷新不能报空对象，也不能重置参数或经验。
	hud._fill.material = null
	hud.glow_strength = 0.0
	hud._process(0.0)
	shader = hud._fill.material as ShaderMaterial
	check(shader != null and shader.shader == hud.FLOW_SHADER and is_equal_approx(shader.get_shader_parameter("visible_fraction"), 0.6), "Live parameter edits repair the old Fill material and preserve progress")
	check(not hud.flow_enabled and hud.glow_strength == 0.0 and shader.get_shader_parameter("sweep_strength") == 0.0 and model.experience == 6, "Material recovery preserves explicit zero and disabled values without granting XP")
	hud._process(0.01)
	check(hud._fill.material == shader, "A repaired material is reused on subsequent frames")
	var empty_shader := ShaderMaterial.new()
	hud._fill.material = empty_shader
	hud.background_opacity = 0.0
	shader = hud._fill.material as ShaderMaterial
	check(shader != empty_shader and shader.shader == hud.FLOW_SHADER and empty_shader.shader == null, "A shaderless resource is repaired without modifying the original resource")
	hud._fill.material = CanvasItemMaterial.new()
	hud.flow_enabled = false
	shader = hud._fill.material as ShaderMaterial
	check(shader != null and shader.shader == hud.FLOW_SHADER and not hud.flow_enabled, "Non-shader Fill material also recovers safely during a toggle")
	hud.flow_enabled = true
	hud._flow_elapsed = hud.flow_interval * 0.5
	hud.pulse(1)
	check(hud._flow_elapsed == 0.0, "Actual pickup feedback wakes an idle sweep")
	hud._process(0.2)
	var running_time := hud._flow_elapsed
	hud.pulse(1)
	check(hud._flow_elapsed == running_time, "Repeated pickups cannot hold a running light band at the beginning")
	hud._process(hud.flow_duration + 0.1)
	check(shader.get_shader_parameter("sweep_strength") == 0.0, "An interval separates sweeps instead of continuous flashing")
	var time := hud._flow_elapsed
	hud.hide()
	hud._process(0.5)
	check(hud._flow_elapsed == time, "Hidden HUD does not advance decorative motion")
	hud.show()
	model.reset()
	check(not hud._glint.visible and not hud._clip.visible and shader.get_shader_parameter("sweep_strength") == 0.0, "Reset clears all effects from an empty experience bar")
	model.rules.level_cap = 2
	model.add_experience(100)
	hud._process(0.2)
	check(hud._value.text == "MAX" and shader.get_shader_parameter("visible_fraction") == 1.0, "Flow also works with MAX without increasing the cap")
	hud.glint_strength = 0.0
	hud._process(0.0)
	check(not hud._glint.visible, "Endpoint sparkle can be disabled independently")
	var pickup: ExperiencePickup = load("res://scenes/growth/experience_pickup.tscn").instantiate()
	root.add_child(pickup)
	pickup.amount = 3
	pickup.advance_visual(0.15)
	check(not pickup._trails.any(func(mote: Sprite3D): return mote.visible), "Resting gems do not produce a light trail")
	check(not pickup.advance(0.15, Vector3(1.8, 0, 0), 2, 0.3, 1, 2, 12, 8), "A partially attracted gem has not been collected")
	check(pickup._trails.size() == 5 and pickup._trails.all(func(mote: Sprite3D): return mote.visible), "Attraction creates the five-mote glowing trail")
	check(pickup._trails[0].modulate.a > pickup._trails[-1].modulate.a and pickup._trails[0].pixel_size > pickup._trails[-1].pixel_size, "Trail tapers in opacity and size")
	var behind := pickup._trails[-1].position.distance_to(pickup._gem.position)
	check(behind <= pickup.trail_length and behind <= pickup._travel_distance, "Trail cannot extend behind an untravelled starting point")
	var before := pickup._trails[0].modulate
	pickup.advance_visual(0.12)
	check(pickup._trails[0].modulate != before and pickup.amount == 3, "Glowing trail shimmers without changing XP")
	pickup.trail_opacity = 0.0
	pickup.advance_visual(0.0)
	check(not pickup._trails.any(func(mote: Sprite3D): return mote.visible), "Trail opacity zero hides every mote")
	pickup.free()
	hud.free()
	await process_frame
	print("Experience flow: %d checks passed" % checks)
	quit.call_deferred()
