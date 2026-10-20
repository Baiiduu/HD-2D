extends SceneTree

const CONTROLLER = preload("res://scripts/rendering/building_occlusion.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func add_building(parent: Node3D, file: String, point: Vector3) -> Node3D:
	var node: Node3D = load("res://scenes/buildings/" + file + ".tscn").instantiate()
	parent.add_child(node)
	node.position = point
	return node

func check_fade(building: Node3D, faded: bool, label: String) -> void:
	for mesh: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
		check(mesh.transparency > 0.6 if faded else is_zero_approx(mesh.transparency), label + ": " + str(building.get_path_to(mesh)))

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var scope := Node3D.new()
	scope.name = "WorldDetails"
	world.add_child(scope)
	var foreign_world := Node3D.new()
	root.add_child(foreign_world)
	var foreign := add_building(foreign_world, "city_cafe", Vector3(0, 0, 4))
	var inside := add_building(scope, "city_hospital", Vector3(12, 0, 4))
	var cafe := add_building(world, "city_cafe", Vector3(0, 0, 4))
	var unrelated := MeshInstance3D.new()
	unrelated.mesh = PlaneMesh.new()
	world.add_child(unrelated)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 5, 12)
	camera.look_at(Vector3(0, 0.6, 0))
	var player := Node3D.new()
	world.add_child(player)
	var controller = CONTROLLER.new()
	controller.building_root = scope
	controller.include_scene_props = true
	controller.player = player
	controller.camera = camera
	world.add_child(controller)
	controller.set_process(false)
	controller.refresh_buildings()
	check(controller._buildings.has(inside.get_instance_id()), "Keep buildings inside WorldDetails")
	check(controller._buildings.has(cafe.get_instance_id()), "A standalone cafe directly under World registers automatically")
	check(not controller._buildings.has(foreign.get_instance_id()), "Do not register buildings belonging to another map")
	check(not controller._buildings.has(unrelated.get_instance_id()), "Do not broaden prop detection to the whole world")
	controller.detect_occlusion()
	controller.advance_fades(1.0)
	check_fade(cafe, true, "Cafe facade and all rooftop parts fade together")
	check_fade(inside, false, "A clear adjacent building stays opaque")
	check_fade(foreign, false, "Another map stays untouched")
	cafe.position.x = -8
	var repair := add_building(world, "city_repair_shop", Vector3(0, 0, 4))
	controller._process(0.5)
	check(controller._buildings.has(repair.get_instance_id()), "Runtime-added repair shop is found by the existing registry poll")
	check_fade(repair, true, "Runtime-added building fades without a per-building script")
	check_fade(cafe, false, "Moving a building out of the way restores its opacity")
	var old_record: RefCounted = controller._buildings.get(repair.get_instance_id())
	repair.reparent(scope, true)
	controller.refresh_buildings()
	check(controller._buildings.get(repair.get_instance_id()) == old_record and old_record != null, "Moving into WorldDetails keeps one geometry record and the current fade")
	controller.include_scene_props = false
	controller.refresh_buildings()
	check(controller._buildings.has(cafe.get_instance_id()), "Group-based building registration also spans the map without prop detection")
	controller.enabled = false
	check_fade(repair, false, "Disabling restores newly added buildings")
	controller.free()
	world.free()
	foreign_world.free()
	await process_frame
	print(JSON.stringify({"suite":"building_registration", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
