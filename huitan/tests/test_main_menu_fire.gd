extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var trail_path := "res://scripts/ui/main_menu_fire_trail.gd"
	check(FileAccess.file_exists(trail_path), "Menu has an adapter for the real ground-fire surface")
	if not failures.is_empty():
		quit(1)
		return
	var shared_include := '#include "res://shaders/combat/ground_fire_surface.gdshaderinc"'
	for shader_path in ["res://shaders/combat/player_fire_trail.gdshader", "res://shaders/ui/main_menu_fire.gdshader"]:
		check(FileAccess.get_file_as_string(shader_path).contains(shared_include), "Gameplay and menu consume one fire shape and burn implementation")
	var timing = load("res://scripts/ui/main_menu_timeline.gd")
	var settings = load("res://data/combat/scenes/world/player/action_visuals.tres")
	var original_width: float = settings.fire_trail_width
	var trail = load(trail_path).new()
	trail.source_visuals = settings
	root.add_child(trail)
	check(trail.segments.size() == 3 and trail.get_child_count() == 3, "Three flight legs reuse three cached ribbon meshes")
	var lifetime: float = settings.fire_trail_fresh_seconds + settings.fire_trail_burn_seconds + settings.fire_trail_ember_seconds
	var initial_nodes: Array[Node] = trail.get_children()
	var first_mesh: ArrayMesh = initial_nodes[0].mesh
	var first_material: ShaderMaterial = initial_nodes[0].material
	for i in trail.segments.size():
		var segment: Dictionary = trail.segments[i]
		var node: MeshInstance2D = initial_nodes[i]
		var material_instance := node.material as ShaderMaterial
		for pair in [["fresh_seconds", "fire_trail_fresh_seconds"], ["burn_seconds", "fire_trail_burn_seconds"], ["ember_seconds", "fire_trail_ember_seconds"], ["energy", "fire_trail_energy"], ["pixels_per_meter", "fire_trail_pixels_per_meter"]]:
			check(is_equal_approx(float(material_instance.get_shader_parameter(pair[0])), float(settings.get(pair[1]))), "Menu reads actual player fire parameter: %s" % pair[0])
		var halfway := float(segment.birth) + float(segment.seconds) * 0.5
		var hero_ground: Vector2 = timing.hero_position(halfway) + timing.FOOT_OFFSET
		check(hero_ground.distance_to(segment.start.lerp(segment.end, 0.5)) < 0.001, "Fire deposition follows the hero's actual position and leg timing")
		var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var across: Vector2 = Vector2(vertices[3].x - vertices[0].x, vertices[3].y - vertices[0].y) / trail.GROUND_PROJECTION
		check(is_equal_approx(across.length(), original_width), "Projected ribbon retains the gameplay width in ground units")
	trail.sample(1.04, 1.0)
	check(trail.get_children().all(func(node): return not node.visible), "Charge preparation cannot draw unborn fire")
	trail.sample(1.3, 1.0)
	check(initial_nodes[0].visible and not initial_nodes[1].visible and not initial_nodes[2].visible, "Only the traveled first leg is eligible before the bounce")
	trail.sample(1.6, 1.0)
	check(initial_nodes[0].visible and initial_nodes[1].visible and not initial_nodes[2].visible, "Bounce leaves the old fire and starts the new leg independently")
	trail.sample(1.55 + lifetime + 0.01, 1.0)
	check(not initial_nodes[0].visible and initial_nodes[2].visible, "Earlier coals expire independently of later flight legs")
	trail.sample(2.65 + lifetime + 0.01, 1.0)
	check(trail.get_children().all(func(node): return not node.visible), "All fire ends at the same gameplay lifetime")
	trail.sample(1.3, 0.0)
	check(trail.get_children().all(func(node): return not node.visible), "Zero fire intensity hides every ribbon")
	trail.sample(1.3, 1.0)
	check(initial_nodes[0].visible and is_equal_approx(float(first_material.get_shader_parameter("effect_clock")), 1.3), "Loop restart resets fire age without stale material state")
	check(initial_nodes == trail.get_children() and initial_nodes[0].mesh == first_mesh and initial_nodes[0].material == first_material, "Sampling does not rebuild nodes, meshes or materials")
	check(settings.fire_trail_width == original_width, "Menu never edits the shared player visual resource")
	trail.queue_free()
	await process_frame
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	menu.audio_enabled = false
	menu.auto_prepare_world = false
	menu.save_preferences = false
	root.add_child(menu)
	await process_frame
	menu.stage.set_process(false)
	menu.stage.timeline.reset(1.73)
	menu.stage._process(0.0)
	check(is_equal_approx(menu.stage._fire_trail.clock, 1.73), "Stage and ribbon share the performance clock")
	menu.stage.reduced_motion = true
	menu.stage._process(0.0)
	var still_clock: float = menu.stage._fire_trail.clock
	menu.stage._process(0.5)
	check(menu.stage._fire_trail.clock == still_clock, "Reduced motion holds fire noise and burning still")
	menu.queue_free()
	await process_frame
	print("MAIN_MENU_FIRE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
