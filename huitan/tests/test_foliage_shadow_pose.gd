extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ",label)

func frames(count := 8) -> void:
	for index in count: await physics_frame
	await process_frame

func run() -> void:
	AudioServer.set_bus_mute(0,true)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("VisualSample").follow_weather = false
	root.add_child(world)
	current_scene = world
	await frames(30)
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var dressing := world.get_node("GroundDressing")
	var terrain: Terrain = world.get_node("Homestead")
	var art: ArtDirection = world.get_node("MapEffects/ArtDirection")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	world.get_node("Player").set_physics_process(false)
	camera.set_process(false)
	camera.snap_to_target()
	var pose := camera.global_transform
	var generated := [terrain._generated,dressing._generated]
	var normals := [sample.surface_normals_enabled,sample.character_normals_enabled,dressing.leaf_normals_enabled,dressing.leaf_normal_strength]
	check(dressing.stable_shadows,"The formal map defaults to stable soft clump shadows")
	var batches: Array[Node] = dressing._generated.find_children("*","MultiMeshInstance3D",true,false)
	var materials: Array[ShaderMaterial] = []
	for batch: MultiMeshInstance3D in batches:
		var material := batch.multimesh.mesh.material as ShaderMaterial
		if material and not materials.has(material): materials.append(material)
	check(not materials.is_empty(),"The fixture has actual foliage shader materials")
	for stable in [true,false,true]:
		dressing.stable_shadows = stable
		for style in [0,1,2,3,0]:
			sample.style = style
			await frames()
			check(dressing.stable_shadows == stable,"Style preserves the independent casting-pose choice")
			check(materials.all(func(material): return material.get_shader_parameter("stable_shadows") == stable),"Every actual foliage material follows the casting-pose choice")
			if DisplayServer.get_name() != "headless":
				check(materials.all(func(material): return RenderingServer.material_get_param(material.get_rid(),&"stable_shadows") == stable),"The GPU-bound foliage materials follow the choice")
		check([terrain._generated,dressing._generated] == generated and camera.global_transform == pose,"Changing the casting pose preserves geometry and camera")
		check([sample.surface_normals_enabled,sample.character_normals_enabled,dressing.leaf_normals_enabled,dressing.leaf_normal_strength] == normals,"Casting-pose changes preserve independent normal maps")
	sample.apply_vegetation_sample()
	await frames()
	check(dressing.stable_shadows,"Refreshing vegetation retains stable soft clump shadows")
	check(is_equal_approx(art.moon_energy,2.85) and is_equal_approx(art.exposure,1.08),"The requested original lighting refinement is retained")
	var catalog = load("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(world)
	check(entries.any(func(entry): return entry.object == dressing and entry.property == "stable_shadows" and entry.common),"The casting-pose toggle is a common editable parameter")
	print("Foliage shadow pose: ",checks," checks; ",failures.size()," failures")
	world.queue_free()
	await frames(2)
	quit(0 if failures.is_empty() else 1)
