extends SceneTree

## Prepared only: no production-file mutation and no GPU requirement.
const HELPER = preload("res://scripts/rendering/empty_water_shadow_gate.gd")
var checks := 0
var failures: Array[String] = []
var world := Node3D.new()
var lantern: Node3D
var water: OmniLight3D
var manager: Node

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func sync(expected: bool, label: String) -> void:
	manager.sync_now()
	check(water.shadow_enabled == expected, label)

func mesh(layers: int) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = BoxMesh.new()
	node.layers = layers
	return node

func find_manager() -> Node:
	for node in root.get_children(true):
		if node.get_script() == HELPER and not node.is_queued_for_deletion(): return node
	return null

func run() -> void:
	# Exercise the selected production source, with the real lantern prefab.
	lantern = load("res://scenes/props/lantern.tscn").instantiate()
	world.add_child(lantern)
	root.add_child(world)
	await process_frame
	water = lantern.get_node("WaterLight")
	manager = root.get_node_or_null("EmptyWaterShadowGate")
	check(is_instance_valid(manager), "first Lantern._ready installs manager")
	if not is_instance_valid(manager):
		world.free()
		quit(1)
		return
	sync(false, "no receiver disables only runtime water shadow")
	check(lantern.shadows_enabled, "source desired remains enabled")
	check(lantern.get_node("Light").shadow_enabled and lantern.get_node("Cone").shadow_enabled, "fill and cone shadows remain enabled")
	var fill := lantern.get_node("Light") as OmniLight3D
	var fill_energy := fill.light_energy
	lantern.set("fill_shadows_enabled", false)
	lantern.apply()
	check(not fill.shadow_enabled and lantern.get_node("Cone").shadow_enabled and water.shadow_enabled, "Local fill shadow switch preserves cone and water shadows")
	check(is_equal_approx(fill.light_energy, fill_energy), "Local shadow switch preserves fill lighting")
	lantern.set("fill_shadows_enabled", true)
	lantern.apply()
	check(fill.shadow_enabled, "Local fill shadow switch can restore shadows")
	lantern.apply()
	check(water.shadow_enabled, "Style/apply honors desired immediately")
	sync(false, "Style/apply is gated at current draw boundary")

	var receiver := mesh(1)
	world.add_child(receiver)
	sync(false, "nonwater receiver does not consume")
	receiver.layers = HELPER.WATER_LAYER
	receiver.hide()
	sync(true, "same-frame hidden receiver layer edit restores")
	receiver.layers = 1
	sync(false, "same-frame receiver layer removal gates")
	# sync_now has entered the draw boundary: node_added must restore before
	# a late creator assigns its final receiving layer after add_child.
	var late := mesh(1)
	world.add_child(late)
	check(water.shadow_enabled, "late addition conservatively restores immediately")
	late.layers = HELPER.WATER_LAYER
	sync(true, "late receiving layer assignment stays restored")
	world.remove_child(late)
	sync(false, "removed receiver no longer consumes")
	world.add_child(late)
	sync(true, "receiver reentry is registered again")
	late.free()
	sync(false, "freed receiver no longer consumes")

	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(16, 16)
	world.add_child(viewport)
	viewport.add_child(mesh(HELPER.WATER_LAYER))
	sync(false, "other World3D does not consume this light")
	viewport.free()
	var voxel := VoxelGI.new()
	world.add_child(voxel)
	sync(true, "unknown VoxelGI preserves desired shadow")
	voxel.free()
	sync(false, "GI removal re-enables empty proof")
	var environment := Environment.new()
	var environment_node := WorldEnvironment.new()
	environment_node.environment = environment
	world.add_child(environment_node)
	environment.sdfgi_enabled = true
	sync(true, "same-frame SDFGI enable preserves desired")
	environment.sdfgi_enabled = false
	sync(false, "same-frame SDFGI disable re-enables empty proof")
	var camera := Camera3D.new()
	camera.environment = Environment.new()
	camera.environment.sdfgi_enabled = true
	world.add_child(camera)
	sync(true, "camera environment SDFGI preserves desired")
	camera.environment.sdfgi_enabled = false
	sync(false, "camera SDFGI removal re-enables empty proof")
	water.light_volumetric_fog_energy = 1.0
	sync(true, "volumetric consumer preserves desired shadow")
	water.light_volumetric_fog_energy = 0.0
	sync(false, "zero volumetric contribution re-enables proof")
	water.light_cull_mask = 1
	sync(true, "changed light mask is outside gate contract")
	water.light_cull_mask = HELPER.WATER_LAYER
	sync(false, "restored exact mask re-enables proof")
	receiver.layers = HELPER.WATER_LAYER
	lantern.shadows_enabled = false
	lantern.apply()
	sync(false, "consumer never overrides source desired false")
	lantern.shadows_enabled = true
	lantern.apply()
	sync(true, "consumer respects restored desired true")
	receiver.layers = 1
	sync(false, "empty proof resumes")
	world.remove_child(lantern)
	await process_frame
	check(water.shadow_enabled, "removed real Lantern restores source shadow")
	world.add_child(lantern)
	await process_frame
	await process_frame
	manager = find_manager()
	check(is_instance_valid(manager), "real Lantern reentry re-registers automatically")
	if is_instance_valid(manager): sync(false, "reentered real Lantern resumes empty gate")
	manager.free()
	check(water.shadow_enabled, "manager exit restores original desired")
	lantern.apply()
	await process_frame
	manager = root.get_node_or_null("EmptyWaterShadowGate")
	check(is_instance_valid(manager), "apply can recreate manager after cleanup")
	sync(false, "recreated manager bootstraps existing geometry")
	world.free()
	await process_frame
	await process_frame
	check(not is_instance_valid(manager), "last registered light removal cleans manager")
	print("Empty water shadow gate functional: ", checks, " checks, failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
