extends SceneTree
const SCRIPT := "res://scripts/rendering/building_occlusion.gd"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func building(parent: Node3D, point: Vector3) -> Node3D:
	var owner := Node3D.new()
	owner.position = point
	owner.add_to_group(&"occlusion_buildings")
	var mesh := MeshInstance3D.new()
	mesh.name = "Model"
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(3, 3, 2)
	mesh.position.y = 1.5
	mesh.material_override = StandardMaterial3D.new()
	owner.add_child(mesh)
	var body := StaticBody3D.new()
	body.name = "StaticBody3D"
	owner.add_child(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	shape.position.y = 1.5
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(3, 3, 2)
	body.add_child(shape)
	parent.add_child(owner)
	return owner

func run() -> void:
	check(ResourceLoader.exists(SCRIPT), "Formal map has a building occlusion controller")
	if ResourceLoader.exists(SCRIPT):
		await behavior_checks()
		await world_checks()
	print(JSON.stringify({"suite":"building_occlusion", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func behavior_checks() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 5, 12)
	camera.look_at(Vector3(0, 0.6, 0))
	var player := Node3D.new()
	world.add_child(player)
	var first := building(world, Vector3(0, 0, 4))
	var second := building(world, Vector3(7, 0, 4))
	var mesh := first.get_node("Model") as MeshInstance3D
	var other := second.get_node("Model") as MeshInstance3D
	var material := mesh.material_override
	var shape := first.get_node("StaticBody3D/Shape") as CollisionShape3D
	var shape_size: Vector3 = shape.shape.size
	var controller = load(SCRIPT).new()
	controller.camera = camera
	controller.player = player
	world.add_child(controller)
	controller.set_process(false)
	controller.refresh_buildings()
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check(mesh.transparency > 0.6 and is_zero_approx(other.transparency), "Only the building between camera and player becomes transparent")
	check(mesh.material_override == material and shape.shape.size == shape_size and not shape.disabled, "Fade keeps existing materials and real collision intact")
	controller.occluded_opacity = 0.45
	controller.advance_fades(0.1)
	check(is_equal_approx(mesh.transparency, 0.55), "Opacity changes apply while a building is already steadily faded")
	controller.occluded_opacity = 0.25
	controller.advance_fades(0.1)
	var cached = controller._buildings[first.get_instance_id()]
	for index in 20: controller.detect_occlusion()
	check(controller._buildings[first.get_instance_id()] == cached, "Repeated detection reuses building geometry records")
	player.position.z = 8
	controller.detect_occlusion()
	controller.advance_fades(0.05)
	check(mesh.transparency > 0.6, "Brief edge changes retain the last fade instead of flickering")
	controller.advance_fades(1.0)
	check(is_zero_approx(mesh.transparency), "A player in front of the building lets it recover")
	var enemy := WaveEnemy.new()
	enemy.spawn_clearance = 0.4
	world.add_child(enemy)
	enemy.add_to_group(&"wave_enemies")
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check(is_zero_approx(mesh.transparency), "A monster behind the building does not trigger fade")
	enemy.dead = true
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check(is_zero_approx(mesh.transparency), "A dead monster no longer holds a building transparent")
	player.position = Vector3.ZERO
	camera.position = Vector3(0, 5, -12)
	camera.look_at(Vector3(0, 0.6, 0))
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check(is_zero_approx(mesh.transparency), "Rotating the view reverses front and behind without moving buildings")
	camera.position = Vector3(0, 5, 12)
	camera.look_at(Vector3(0, 0.6, 0))
	first.position.x = 7
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check(is_zero_approx(mesh.transparency), "Moving an existing building invalidates cached world bounds")
	first.position.x = 0
	shape.shape.size = Vector3(0.2, 0.2, 0.2)
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check(is_zero_approx(mesh.transparency), "Shape edits invalidate cached occluder bounds")
	# 医院采用分段碰撞；凹角的空区不能仅凭整栋外包围盒触发淡化。
	shape.shape.size = Vector3(2, 3, 2)
	shape.position = Vector3(-2, 1.5, 0)
	var wing := CollisionShape3D.new()
	wing.shape = BoxShape3D.new()
	wing.shape.size = Vector3(2, 3, 2)
	wing.position = Vector3(0, 1.5, -2)
	shape.get_parent().add_child(wing)
	player.position = Vector3(-2, 0, 2)
	camera.position = Vector3(-6, 5, -2)
	camera.look_at(player.position + Vector3.UP * 0.75)
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check(is_zero_approx(mesh.transparency), "Empty corners in a multi-part building remain clear")
	shape.shape.size = shape_size
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	controller.enabled = false
	check(is_zero_approx(mesh.transparency), "Disabling restores original instance transparency immediately")
	controller.enabled = true
	mesh.transparency = 0.15
	controller.refresh_buildings()
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	controller.queue_free()
	await process_frame
	await process_frame
	check(is_equal_approx(mesh.transparency, 0.15), "Removing the controller restores authored transparency")
	world.free()
	await process_frame

func world_checks() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	root.add_child(world)
	var controller = world.get_node("BuildingOcclusion")
	controller.set_process(false)
	world.get_node("Player").set_physics_process(false)
	world.get_node("WavePrototype").set_physics_process(false)
	controller.camera.set_process(false)
	for index in 12: await process_frame
	controller.refresh_buildings()
	check(controller._buildings.size() == 7, "Formal World registers only its seven native buildings")
	check(not world.get_node("Player/Sprite").occlusion_outline_enabled and not world.get_node("WavePrototype").enemy_occlusion_outline_enabled, "Formal player and all wave monsters disable through-building outlines")
	var style = world.get_node("VisualSample")
	var original_style: int = style.style
	for index in 4:
		style.style = index
		style.apply_style()
		check(not world.get_node("Player/Sprite").occlusion_outline_enabled, "Changing lighting Style preserves the disabled outline")
	style.style = original_style
	style.apply_style()
	var records: Array = controller._buildings.values()
	var first = records[0]
	first.refresh_bounds()
	check(not first.surfaces.is_empty() and not first.shapes.is_empty(), "Actual imported models have reusable surfaces and segmented occluders")
	var center: Vector3 = first.shapes[0].global_position
	controller.player.global_position = center + Vector3(0, -0.75, -7)
	controller.camera.global_position = center + Vector3(0, 1, 12)
	controller.camera.look_at(center + Vector3(0, 0, -7))
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check(first.surfaces[0].transparency > 0.6, "Actual hospital or shop geometry fades when it blocks the player")
	controller.world_entry.play(false)
	controller._process(0.1)
	check(is_zero_approx(first.surfaces[0].transparency), "Entry cinematic keeps building facades opaque")
	controller.world_entry.advance(controller.world_entry.settings.duration_seconds)
	check(not world.get_node("Player/Sprite").occlusion_outline_enabled, "Finishing entry preserves the disabled player outline")
	controller.startup.open_menu()
	controller._process(0.1)
	check(is_zero_approx(first.surfaces[0].transparency), "Opening the main menu restores building opacity immediately")
	world.free()
	await process_frame
	await process_frame
