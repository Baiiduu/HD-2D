extends SceneTree

const MONUMENT := preload("res://scenes/buildings/cyber_armillary_monument.tscn")
var failures := 0
var checks := 0

class Session extends WavePrototype:
	func _ready() -> void:
		set_process(false)
		set_physics_process(false)

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var session := Session.new()
	session.name = "WavePrototype"
	world.add_child(session)
	var monument := MONUMENT.instantiate()
	world.add_child(monument)
	var motion := monument.get_node_or_null("AuroraMotion") as AnimationPlayer
	check(motion != null, "The globe has an engine-driven material animation")
	if motion:
		await process_frame
		await process_frame
		check(motion in session._combat_nodes, "The scene-local clock joins the existing combat freeze mechanism")
		var material := monument.get_node("Model/Globe").get_active_material(0) as ShaderMaterial
		check(material.resource_local_to_scene, "Each monument owns its clock without duplicating textures")
		motion.seek(2.0, true)
		await create_timer(0.03).timeout
		var stamp: float = material.get_shader_parameter("motion_phase")
		check(stamp > 0.0, "The engine animation advances the material phase")
		session.set_combat_frozen(true)
		await create_timer(0.03).timeout
		var held: float = material.get_shader_parameter("motion_phase")
		check(is_equal_approx(stamp, held), "Combat freeze holds the material at its current phase")
		session.set_combat_frozen(false)
		await create_timer(0.03).timeout
		var resumed: float = material.get_shader_parameter("motion_phase")
		check(resumed > held and resumed - held < 0.1, "Resume continues smoothly without catching up paused time")
		motion.seek(19.99, true)
		motion.advance(0.02)
		var wrapped: float = material.get_shader_parameter("motion_phase")
		check(wrapped >= 0.0 and wrapped < 0.02, "The bounded phase loops without accumulating unbounded time")
		var twin := MONUMENT.instantiate()
		world.add_child(twin)
		var other: ShaderMaterial = twin.get_node("Model/Globe").get_active_material(0)
		check(other != material, "A second monument has an independent material clock")
		check(other.get_shader_parameter("albedo_atlas") == material.get_shader_parameter("albedo_atlas"), "Instances reuse the native color texture")
		check(other.get_shader_parameter("orm_atlas") == material.get_shader_parameter("orm_atlas"), "Instances reuse the packed motion and emission masks")
		twin.free()
		monument.free()
		check(session._combat_nodes.is_empty(), "Leaving the scene releases the clock registration")
	world.free()
	await process_frame
	print("Cyber armillary motion: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
