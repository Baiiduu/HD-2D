extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var effect: LightPierceEffect = load("res://scenes/combat/light_pierce_effect.tscn").instantiate()
	var prism: PrismRicochetEffect = load("res://scenes/combat/prism_ricochet_effect.tscn").instantiate()
	scene.add_child(effect)
	scene.add_child(prism)
	check(effect.head_texture.get_size() == Vector2(48, 16) and effect.trail_texture.get_size() == Vector2(128, 16), "A02 uses the native small pixel assets instead of the HD textures")
	check(effect.impact_frames.get_frame_count(&"impact") == 8, "Every generated impact frame is retained")
	for index in 8:
		var frame := effect.impact_frames.get_frame_texture(&"impact", index) as AtlasTexture
		check(frame and frame.get_size() == Vector2(64, 48) and Rect2(Vector2.ZERO, frame.atlas.get_size()).encloses(frame.region), "Each impact samples only its native frame inside the delivered atlas")
	check(effect.head_texture.get_image().detect_alpha() != Image.ALPHA_NONE and effect.trail_texture.get_image().detect_alpha() != Image.ALPHA_NONE, "Native head and dash gaps retain real alpha")
	check(prism.trail_texture.resource_path == "res://assets/meowa/combat/light_pierce/trail.png" and prism._feedback.impact_frames.resource_path == "res://assets/meowa/combat/light_pierce/impact_frames.tres", "A03 retains its own prior trail and crystalline contact animation")
	check(prism._feedback.impact_frames != effect.impact_frames and not prism._feedback.preserve_trail_pixel_scale, "Updating A02 never reskins A03 through a shared scene")
	effect.transform = Transform3D(Basis.from_euler(Vector3(0, 0.7, 0)).scaled(Vector3(1.2, 0.9, 1.1)), Vector3(3, 0.1, -2))
	var origin := Vector3(2, 0.1, 4)
	var direction := Vector3(1, 0, -0.5).normalized()
	var mesh := effect._trail.mesh
	for yaw in [0.0, 45.0, 90.0, 180.0]:
		camera.rotation_degrees = Vector3(-32, yaw, 0)
		effect.launch(origin, direction, 8.0, true)
		effect.set_process(false)
		for distance in [0.25, 1.0, 3.2, 6.0]:
			effect.advance_flight(distance)
			if effect._trail.visible:
				var texture_rect: Vector4 = effect._trail_material.get_shader_parameter("frame_rect")
				var texel_world_size := effect._trail.global_basis.x.length() / (effect.trail_texture.get_width() * texture_rect.z)
				check(is_equal_approx(texel_world_size, effect.trail_length / effect.trail_texture.get_width()), "Short and full trails retain the same world pixel size at every camera angle")
				var trail_tip := effect._trail.global_position + effect._trail.global_basis.x
				check((effect.head_tip_position() - trail_tip).dot(direction) >= effect.head_tip_anchor * effect.head_width - 0.00005, "Every dash stays behind the needle instead of being covered by its bright core")
			else:
				check(distance <= effect.head_tip_anchor * effect.head_width, "Startup never draws the delayed trail behind the casting origin")
			check(effect.head_tip_position().distance_to(origin + Vector3.UP * effect.flight_height + direction * distance) < 0.00005, "Visible needle tip remains on the real projectile position under Q/E")
			check(effect._trail.mesh == mesh, "Pixel trail motion continues to reuse the shared mesh")
		var tip := effect.head_tip_position()
		camera.rotation_degrees.y += 15.0
		effect._process(0.0)
		check(effect.head_tip_position().distance_to(tip) < 0.00005, "Rotating a stationary view never drifts the anchored needle tip")
	# 镜头侧向看见完整长度，正对弹道时长度按俯角投影，避免遮住前方敌人。
	var projected_lengths: Array[float] = []
	for yaw in [0.0, 90.0]:
		camera.rotation_degrees = Vector3(-25.414, yaw, 0)
		effect.launch(origin, Vector3.RIGHT, 8.0, true)
		effect.set_process(false)
		effect.advance_flight(3.2)
		var head_axis := effect._head.global_basis.x
		projected_lengths.append(Vector2(head_axis.dot(camera.global_basis.x), head_axis.dot(camera.global_basis.y)).length())
	check(is_equal_approx(projected_lengths[0], 1.0) and projected_lengths[1] < 0.5, "Needle naturally foreshortens into depth instead of remaining a full billboard at Q/E 90 degrees")
	effect.preserve_trail_pixel_scale = false
	check(effect._trail_material.get_shader_parameter("frame_rect") == Vector4(0, 0, 1, 1), "Remote sampling toggle releases the old cropped texture rectangle")
	effect.preserve_trail_pixel_scale = true
	check(effect._head_material.get_shader_parameter("edge_fade") == 0.0, "Pixel tip stays clear when sampling is re-enabled")
	effect.stop()
	check(not effect.is_processing() and not effect._head.visible and not effect._trail.visible, "The new visual still stops all idle work")
	scene.free()
	for frame in 3: await process_frame
	print("A02 pixel style: %d checks, %d failures" % [checks, failures])
	quit.call_deferred(1 if failures else 0)
