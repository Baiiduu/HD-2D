extends "res://tests/test_creature_flat_chase.gd"
const NativeLoader = preload("res://scripts/combat/native_swarm_loader.gd")
var kernel: RefCounted

func _initialize() -> void:
	kernel = NativeLoader.create()
	super._initialize()

func creature(id: String, point := Vector3(-3, 0.001, 0)) -> CreatureEnemy:
	var actor := super.creature(id, point)
	actor._native_swarm = kernel
	return actor

func run() -> void:
	check(kernel != null and kernel.has_method("move_body"), "Native ordinary movement entry exists")
	if not kernel or not kernel.has_method("move_body"): quit(1); return
	await super.run()

func obstacle_checks() -> void:
	await super.obstacle_checks()
	var monument := ArmillaryMonument.new()
	monument.flowers_enabled = false
	monument.garden_lights_enabled = false
	monument.scale = Vector3.ONE * 0.5
	world.add_child(monument)
	await settle(8)
	var actor := creature("leaf_charger", Vector3(-1.8, 0.001, -0.93))
	for frame in 150:
		await settle(1)
		motion(actor, Vector3(1.020119, 0, 2.282402).normalized(), 2.5)
		intact(actor, "actual octagonal monument foot")
	clear_actors()
	monument.queue_free()
	await settle()

func terrain_checks() -> void:
	var actor := creature("leaf_charger")
	var before: int = kernel.get_metrics().direct_moves
	motion(actor, Vector3.RIGHT)
	check(actor._ground_moved and kernel.get_metrics().direct_moves > before, "Forced motion exercises the native body solver")
	terrain.data.changed.emit()
	await settle()
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(actor._ground_moved, "Rebuilt floor is read live by the native solver")
	terrain.data.set_overlay(Vector2i(6,6), TerrainData.OVERLAY_BRIDGE, true)
	await settle()
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(not actor._ground_moved, "Complex terrain uses the original physics fallback")
	terrain.data.set_overlay(Vector2i(6,6), TerrainData.OVERLAY_BRIDGE, false)
	await settle()
	reset_actor(actor, Vector3(-3,0.001,0), true)
	actor.apply_stun(0.3)
	actor._physics_process(DELTA)
	check(not actor._ground_moved, "Native mode leaves stun on the original solver")
	clear_actors()
