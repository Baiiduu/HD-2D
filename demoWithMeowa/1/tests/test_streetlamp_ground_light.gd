extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func blocks(mesh: MeshInstance3D, start: Vector3, end: Vector3) -> bool:
	var local_start := mesh.to_local(start)
	var local_end := mesh.to_local(end)
	var faces := mesh.mesh.get_faces()
	for index in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(local_start, local_end, faces[index], faces[index + 1], faces[index + 2]) != null:
			return true
	return false

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for size in [1.0, 0.4, 0.3]:
		var lamp := load("res://scenes/buildings/plaza_streetlamp.tscn").instantiate() as PlazaStreetlamp
		lamp.scale = Vector3.ONE * size
		lamp.rotation_degrees.y = 65
		world.add_child(lamp)
		for frame in 3: await process_frame
		var metal := lamp.get_node("Geometry/Metal") as MeshInstance3D
		var brass := lamp.get_node("Geometry/Brass") as MeshInstance3D
		for head in lamp._heads:
			var cone := head.get_node("Cone") as SpotLight3D
			var x: float = head.position.x
			var ground := lamp.to_global(Vector3(x, 0, 0.65))
			for light_name in ["Cone", "Light", "WaterLight"]:
				var light: Light3D = head.get_node(light_name)
				check(not blocks(metal, light.global_position, ground) and not blocks(brass, light.global_position, ground), "Actual %s ground-light ray exits the lantern at scale %s" % [light_name, size])
			var post_start := lamp.to_global(Vector3(-0.3, 1.0, 0))
			var post_end := lamp.to_global(Vector3(0.3, 1.0, 0))
			check(blocks(metal, post_start, post_end) and metal.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and cone.shadow_enabled,
				"Pole still blocks light and real scene shadows stay enabled")
		lamp.queue_free()
		await process_frame
	world.queue_free()
	await process_frame
	print("Streetlamp ground light: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
