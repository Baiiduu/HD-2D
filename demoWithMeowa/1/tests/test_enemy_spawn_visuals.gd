extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func spawn_checks(id: String, warning: float) -> void:
	var path := "res://data/enemies/" + ("wave_slime" if id == "slime" else id) + ".tres"
	var definition := load(path) as WaveMeleeEnemyDefinition
	var actor := definition.scene.instantiate() as SlimeEnemy
	var visual := actor.get_node("Sprite") as Sprite3D
	var original_scale := Vector3(0.8, 1.1, 0.9)
	var original_color := Color(0.9, 0.7, 0.5, 0.65)
	visual.scale = original_scale
	visual.modulate = original_color
	var pixel_size := visual.pixel_size
	actor.configure_wave({"player":null, "terrain":null, "camera":camera,
		"navigation":TerrainPath.new(), "attack_root":null,
		"damage_player":Callable(), "request_spawn":Callable()}, definition, warning)
	world.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	var label := "%s legacy_warning=%s" % [id, warning]
	check(actor.spawn_delay == 0.0, label + ": active immediately even with old warning configuration")
	check(visual.scale.is_equal_approx(original_scale), label + ": original size before first process")
	check(is_equal_approx(visual.modulate.a, original_color.a), label + ": original opacity before first process")
	for frame in 8:
		actor._process(1.0 / 60.0)
		check(visual.scale.is_equal_approx(original_scale), label + ": no miniature after birth")
	check(is_equal_approx(visual.modulate.a, original_color.a), label + ": no translucent spawn warning")
	check(visual.pixel_size == pixel_size and visual.texture != null, label + ": native pixel size and own texture retained")
	var health := actor.health
	actor.take_damage(1.0)
	check(actor.health == health - 1.0, label + ": accepts real damage immediately after birth")
	actor._process(0.0)
	check(visual.scale.is_equal_approx(original_scale) and is_equal_approx(visual.modulate.a, original_color.a), label + ": damage feedback preserves size and opacity")
	actor.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	for id in ["slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		for warning in [-1.0, 0.0, 0.8]: spawn_checks(id, warning)
	# 地图预览不走波次出生预告，保留其独立尺寸和透明度。
	var preview := load("res://scenes/enemies/slime.tscn").instantiate() as SlimeEnemy
	preview.get_node("Sprite").scale = Vector3.ONE * 0.85
	preview.get_node("Sprite").modulate.a = 0.7
	world.add_child(preview)
	preview.set_process(false)
	preview.set_physics_process(false)
	preview._process(0.0)
	check(preview.sprite.scale.is_equal_approx(Vector3.ONE * 0.85) and is_equal_approx(preview.sprite.modulate.a, 0.7), "Non-wave preview keeps its original appearance")
	await process_frame
	world.queue_free()
	for frame in 5:
		await physics_frame
		await process_frame
	print("Enemy spawn visuals: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
